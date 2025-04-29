import Foundation
import Brokerage
import TradingStrategy

public final class TradeAggregator: Hashable {
    public var isTradeEntryEnabled: Bool = false
    public var isTradeExitEnabled: Bool = false
    public var isTradeEntryNotificationEnabled: Bool = true
    public var isTradeExitNotificationEnabled: Bool = true
    public var minConfirmations: Int = 1
    
    public let id = UUID()
    public let contract: any Contract
    private var marketOrder: MarketOrder?
    private var tradeSignals: Set<Request> = []
    private let tradeQueue = DispatchQueue(label: "TradeAggregatorQueue", attributes: .concurrent)
    
    private var getNextTradingAlertsAction: (() -> Annoucment?)?
    private var tradeEntryNotificationAction: ((_ trade: Trade, _ recentBar: Klines) -> Void)?
    private var tradeExitNotificationAction: ((_ trade: Trade, _ recentBar: Klines) -> Void)?
    private var patternInformationChangeAction: ((_ patternInformation: [String: Bool]) -> Void)?
    
    public init(
        contract: any Contract,
        marketOrder: MarketOrder? = nil,
        getNextTradingAlertsAction: (() -> Annoucment?)? = nil,
        tradeEntryNotificationAction: ((_ trade: Trade, _ recentBar: Klines) -> Void)? = nil,
        tradeExitNotificationAction: ((_ trade: Trade, _ recentBar: Klines) -> Void)? = nil,
        patternInformationChangeAction: ((_ patternInformation: [String: Bool]) -> Void)? = nil
    ) {
        self.marketOrder = marketOrder
        self.contract = contract
        self.getNextTradingAlertsAction = getNextTradingAlertsAction
        self.tradeEntryNotificationAction = tradeEntryNotificationAction
        self.tradeExitNotificationAction = tradeExitNotificationAction
        self.patternInformationChangeAction = patternInformationChangeAction
    }
    
    deinit {
        getNextTradingAlertsAction = nil
        tradeEntryNotificationAction = nil
        tradeExitNotificationAction = nil
    }
    
    public func registerTradeSignal(_ request: Request) async {
        let strategy = await request.watcherState.getStrategy()
        patternInformationChangeAction?(strategy.patternInformation)
        if strategy.patternIdentified {
            let contract = contract.label
            let count = tradeQueue.sync(flags: .barrier) { [weak self] in
                self?.tradeSignals.insert(request)
                return self?.tradeSignals.count ?? 0
            }
            
            if count >= minConfirmations {
                let matchingRequest = tradeQueue.sync(flags: .barrier) { [weak self] in
                    self?.tradeSignals.first(where: { $0.contract.label == contract })
                }
                guard let matchingRequest else {
                    print("🔴 Failure to find matching request")
                    return
                }
                await enterTradeIfStrategyIsValidated(matchingRequest)
                tradeQueue.sync(flags: .barrier) { [weak self] in
                    self?.tradeSignals = []
                }
            } else {
                print("⏳ Waiting for more confirmations for \(contract): \(tradeSignals.count)/\(minConfirmations)")
            }
        } else {
            tradeQueue.sync(flags: .barrier) { [weak self] in
                _ = self?.tradeSignals.remove(request)
            }
        }
        await manageActiveTrade(request)
    }
    
    private func enterTradeIfStrategyIsValidated(_ request: Request) async {
        guard !Task.isCancelled else { return }
        let hasNoActiveTrade = await request.watcherState.getActiveTrade() == nil
        guard hasNoActiveTrade else { return }
        let strategy = await request.watcherState.getStrategy()
        guard strategy.patternIdentified, let entryBar = strategy.candles.last else { return }
        
        if request.isSimulation {
            let units = strategy.shouldEnterWitUnitCount(
                entryBar: entryBar,
                equity: 1_000_000,
                feePerUnit: 50,
                nextAnnoucment: nil
            )
            let initialStopLoss = strategy.adjustStopLoss(entryBar: entryBar) ?? 0
            let trade = Trade(
                entryBar: entryBar,
                price: entryBar.priceClose,
                stopPrice: initialStopLoss,
                units: Double(units)
            )
            await request.watcherState.updateActiveTrade(trade)
            print("🟤 enter trade: ", trade)
        } else if let account = marketOrder?.account {
            let nextEvent = getNextTradingAlertsAction?()
            let units = strategy.shouldEnterWitUnitCount(
                entryBar: entryBar,
                equity: account.buyingPower,
                feePerUnit: 50,
                nextAnnoucment: nextEvent
            )
            guard units > 0 else { return }
            let initialStopLoss = strategy.adjustStopLoss(entryBar: entryBar)
            print("✅ enterTradeIfStrategyIsValidated, symbol: \(request.symbol): interval: \(request.interval)")
            print("✅ enterTradeIfStrategyIsValidated units: ", units)
            print("✅ enterTradeIfStrategyIsValidated stopLoss: ", initialStopLoss ?? 0)
            guard let initialStopLoss else { return }
            
            await evaluateMarketCoonditions(
                trade:
                    Trade(
                        entryBar: entryBar,
                        price: entryBar.priceClose,
                        stopPrice: initialStopLoss,
                        units: Double(units)
                    ),
                request: request
            )
        }
    }
    
    private func evaluateMarketCoonditions(trade: Trade, request: Request) async {
        let marketOpen = await request.watcherState.getTradingHours()?.isMarketOpen()
        print("✅ evaluateMarketCoonditions: ", marketOpen as Any)
        guard
            let marketOpen,
            marketOpen.isOpen,
            let timeUntilClose = marketOpen.timeUntilChange,
            timeUntilClose > (1_800 * 6)
        else { return }
        
        let hasNoActiveTrade = await request.watcherState.getActiveTrade() == nil
        guard hasNoActiveTrade else { return }

        guard let quote = await request.watcherState.getQuote() else {
            print("⚠️ No quote available, cannot enter trade.")
            return
        }

        let orderPrice: Double
        if trade.entryBar.isLong, let ask = quote.askPrice {
            orderPrice = ask
        } else if !trade.entryBar.isLong, let bid = quote.bidPrice {
            orderPrice = bid
        } else {
            print("⚠️ No bid/ask available, fallback to entry bar close.")
            orderPrice = trade.price
        }

        let tradeWithQuotePrice = Trade(
            entryBar: trade.entryBar,
            price: orderPrice,
            stopPrice: trade.stopPrice,
            units: trade.units
        )

        await request.watcherState.updateActiveTrade(tradeWithQuotePrice)

        if isTradeEntryNotificationEnabled {
            tradeEntryNotificationAction?(tradeWithQuotePrice, tradeWithQuotePrice.entryBar)
        }
        
        guard isTradeEntryEnabled else { return }

        do {
            try await placeOrder(trade: tradeWithQuotePrice, isLong: trade.entryBar.isLong)
        } catch {
            print("🔴 Failed placing initial order: \(error)")
        }
    }
    
    private func placeOrder(trade: Trade, isLong: Bool) async throws {
        guard let marketOrder else { return }

        let side: OrderAction = isLong ? .buy : .sell
        try marketOrder.makeLimitWithStopOrder(
            contract: contract,
            action: side,
            price: trade.price,
            stopPrice: trade.stopPrice,
            quantity: trade.units
        )
    }
    
    private func cancelPendingOrders(activeTrade: Trade, recentBar: Klines) {
        guard activeTrade.entryBar.timeClose == recentBar.timeOpen else { return }
        guard let account = marketOrder?.account else { return }
        guard let order = account.orders.first(where: { $0.value.symbol == contract.symbol }) else { return }
        do {
            try marketOrder?.cancelOrder(orderId: order.value.orderID)
        } catch {
            print("Error canceling pending orders: \(error)")
        }
    }
    
    private func manageActiveTrade(_ request: Request) async {
        guard !Task.isCancelled else { return }
        let strategy = await request.watcherState.getStrategy()
        
        guard
            let activeTrade = await request.watcherState.getActiveTrade(),
            let recentBar = strategy.candles.last,
            activeTrade.entryBar.timeOpen != recentBar.timeOpen
        else { return }
        
        cancelPendingOrders(activeTrade: activeTrade, recentBar: recentBar)
        
        let nextEvent = getNextTradingAlertsAction?()
        let shouldExit = strategy.shouldExit(entryBar: activeTrade.entryBar, nextAnnoucment: nextEvent)
        let isLongTrade = activeTrade.entryBar.isLong
        
        let wouldHitStopLoss = isLongTrade
            ? activeTrade.stopPrice >= recentBar.priceClose
            : activeTrade.stopPrice <= recentBar.priceClose

        if shouldExit, isTradeExitNotificationEnabled {
            tradeExitNotificationAction?(activeTrade, recentBar)
        }
        
        if (shouldExit || wouldHitStopLoss) {
            let quote = await request.watcherState.getQuote()
            let exitPrice = quote?.lastPrice ?? recentBar.priceClose

            if request.isSimulation {
                let profit = isLongTrade
                    ? exitPrice - activeTrade.price
                    : activeTrade.price - exitPrice
                print("❌ profit: \(profit) entry: \(activeTrade.price), exit: \(exitPrice), stopLoss: \(wouldHitStopLoss)")
                await request.watcherState.updateActiveTrade(nil)
            } else if isTradeExitEnabled {
                guard let account = marketOrder?.account else { return }
                guard let position = account.positions.first(where: { $0.label == contract.label }) else { return }

                do {
                    try marketOrder?.makeLimitOrder(
                        contract: contract,
                        action: isLongTrade ? .sell : .buy,
                        price: exitPrice,
                        quantity: position.quantity
                    )
                    print("❌ Exiting trade, exitPrice: \(exitPrice)")
                    await request.watcherState.updateActiveTrade(nil)
                } catch {
                    print("🔴 Error exiting trade: \(error)")
                }
            }
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(contract.label)
        hasher.combine(id)
    }
    
    public static func == (lhs: TradeAggregator, rhs: TradeAggregator) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: Types
    
    public struct Request: Hashable {
        let isSimulation: Bool
        let watcherState: Watcher.WatcherStateActor
        let contract: any Contract
        let interval: TimeInterval
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(contract.label)
            hasher.combine(interval)
        }
        
        public static func == (lhs: Request, rhs: Request) -> Bool {
            return lhs.contract.label == rhs.contract.label && lhs.interval == rhs.interval
        }
    }
}

public extension TradeAggregator.Request {
    var symbol: String { contract.symbol }
}
