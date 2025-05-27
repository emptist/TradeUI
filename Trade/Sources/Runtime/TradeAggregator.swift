import Foundation
import Brokerage
import TradingStrategy

public final class TradeAggregator: Hashable {
    public var isTradeEntryEnabled: Bool = true
    public var isTradeExitEnabled: Bool = true
    public var isTradeEntryNotificationEnabled: Bool = true
    public var isTradeExitNotificationEnabled: Bool = true
    public var minConfirmations: Int = 1
    
    public let id = UUID()
    public let contract: any Contract
    private var marketOrder: MarketOrder?
    private var tradeSignals: Set<Request> = []
    private let stats = TradeStats()
    private let tradeQueue = DispatchQueue(label: "TradeAggregatorQueue", attributes: .concurrent)
    
    private var getNextTradingAlertsAction: (() -> Annoucment?)?
    private var tradeEntryNotificationAction: ((_ trade: Trade, _ recentBar: Klines) -> Void)?
    private var tradeExitNotificationAction: ((_ trade: Trade, _ recentBar: Klines) -> Void)?
    private var patternInformationChangeAction: ((_ patternInformation: [String: Double]) -> Void)?
    
    public init(
        contract: any Contract,
        marketOrder: MarketOrder? = nil,
        getNextTradingAlertsAction: (() -> Annoucment?)? = nil,
        tradeEntryNotificationAction: ((_ trade: Trade, _ recentBar: Klines) -> Void)? = nil,
        tradeExitNotificationAction: ((_ trade: Trade, _ recentBar: Klines) -> Void)? = nil,
        patternInformationChangeAction: ((_ patternInformation: [String: Double]) -> Void)? = nil
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
        if let _ = strategy.patternIdentified {
            let contractLabel = contract.label
            
            let alignedRequests: [(Request, Signal?)] =
            await tradeQueue.sync(flags: .barrier) {
                self.tradeSignals.insert(request)
                return Array(self.tradeSignals)
            }.asyncMap { req async in
                let sig = await req.watcherState.getStrategy().patternIdentified
                return (req, sig)
            }
            
            // Count votes per signal
            let groupedBySignal = Dictionary(grouping: alignedRequests, by: { $0.1 })
            let (majoritySignal, matchingRequests) = groupedBySignal
                .filter { $0.key != nil }
                .max(by: { $0.value.count < $1.value.count }) ?? (nil, [])
            
            if let confirmedSignal = majoritySignal, matchingRequests.count >= minConfirmations {
                let avgConfidence = matchingRequests
                    .compactMap { $0.1?.confidence }
                    .reduce(0, +) / Float(matchingRequests.count)
                
                guard avgConfidence > 0.0 else {
                    print("⚠️ Insufficient confidence (\(avgConfidence)) for signal \(confirmedSignal)")
                    return
                }
                
                let matchingRequest = tradeQueue.sync(flags: .barrier) { [weak self] in
                    self?.tradeSignals.first(where: { $0.contract.label == contractLabel })
                }
                guard let matchingRequest else {
                    print("🔴 Failure to find matching request")
                    return
                }
                await enterTradeIfStrategyIsValidated(matchingRequest, signal: confirmedSignal)
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
    
    private func enterTradeIfStrategyIsValidated(_ request: Request, signal: Signal) async {
        guard !Task.isCancelled else { return }
        let hasNoActiveTrade = await request.watcherState.getActiveTrade() == nil
        guard hasNoActiveTrade else { return }
        let strategy = await request.watcherState.getStrategy()
        guard let _ = strategy.patternIdentified, let entryBar = strategy.candles.last else { return }
        
        if request.isSimulation {
            let units = strategy.shouldEnterWitUnitCount(
                signal: signal,
                entryBar: entryBar,
                equity: 1_000_000,
                feePerUnit: 50,
                nextAnnoucment: nil
            )
            let initialStopLoss = strategy.adjustStopLoss(signal: signal, entryBar: entryBar) ?? 0
            let trade = Trade(
                entryBar: entryBar,
                signal: signal,
                price: entryBar.priceClose,
                stopPrice: initialStopLoss,
                units: Double(units),
                patternInformation: strategy.patternInformation
            )
            await request.watcherState.updateActiveTrade(trade)
//            print("🟤 enter trade: ", trade)
//            print("🟤 signal: \(signal)")
//            print("🟤 entryBar.isLong: \(trade.entryBar.isLong)")
        } else if let account = marketOrder?.account {
            let nextEvent = getNextTradingAlertsAction?()
            let units = strategy.shouldEnterWitUnitCount(
                signal: signal,
                entryBar: entryBar,
                equity: account.buyingPower,
                feePerUnit: 50,
                nextAnnoucment: nextEvent
            )
            guard units > 0 else { return }
            let initialStopLoss = strategy.adjustStopLoss(signal: signal, entryBar: entryBar)
            print("✅ enterTradeIfStrategyIsValidated signal: \(signal)")
            print("✅ enterTradeIfStrategyIsValidated symbol: \(request.symbol): interval: \(request.interval)")
            print("✅ enterTradeIfStrategyIsValidated units: ", units)
            print("✅ enterTradeIfStrategyIsValidated stopLoss: ", initialStopLoss ?? 0)
            guard let initialStopLoss else { return }
            
            await evaluateMarketCoonditions(
                trade:
                    Trade(
                        entryBar: entryBar,
                        signal: signal,
                        price: entryBar.priceClose,
                        stopPrice: initialStopLoss,
                        units: Double(units),
                        patternInformation: strategy.patternInformation
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
        if trade.signal.isLong, let ask = quote.askPrice {
            orderPrice = ask
        } else if !trade.signal.isLong, let bid = quote.bidPrice {
            orderPrice = bid
        } else {
            print("⚠️ No bid/ask available, fallback to entry bar close.")
            orderPrice = trade.price
        }

        let tradeWithQuotePrice = Trade(
            entryBar: trade.entryBar,
            signal: trade.signal,
            price: orderPrice,
            stopPrice: trade.stopPrice,
            units: trade.units,
            patternInformation: trade.patternInformation
        )

        await request.watcherState.updateActiveTrade(tradeWithQuotePrice)

        if isTradeEntryNotificationEnabled {
            tradeEntryNotificationAction?(tradeWithQuotePrice, tradeWithQuotePrice.entryBar)
        }
        
        guard isTradeEntryEnabled else { return }

        do {
            try await placeOrder(trade: tradeWithQuotePrice, isLong: trade.isLong)
        } catch {
            print("🔴 Failed placing initial order: \(error)")
        }
    }
    
    private func placeOrder(trade: Trade, isLong: Bool) async throws {
        guard let marketOrder else { return }

        let side: OrderAction = isLong ? .buy : .sell
        try await marketOrder.makeLimitWithStopOrder(
            contract: contract,
            action: side,
            price: trade.price,
            stopPrice: trade.stopPrice,
            quantity: trade.units
        )
    }
    
    private func manageActiveTrade(_ request: Request) async {
        guard !Task.isCancelled else { return }
        let strategy = await request.watcherState.getStrategy()
        
        guard
            let activeTrade = await request.watcherState.getActiveTrade(),
            let recentBar = strategy.candles.last,
            activeTrade.entryBar.timeOpen != recentBar.timeOpen
        else { return }
        
        let nextEvent = getNextTradingAlertsAction?()
        let shouldExit = strategy.shouldExit(signal: activeTrade.signal, entryBar: activeTrade.entryBar, nextAnnoucment: nextEvent)
        let isLongTrade = activeTrade.isLong
        
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
                
                let result = TradeResult(
                    isLong: isLongTrade,
                    entryPrice: activeTrade.price,
                    exitPrice: exitPrice,
                    profit: profit,
                    stopLossHit: wouldHitStopLoss,
                    confidence: activeTrade.signal.confidence,
                    patternInformation: activeTrade.patternInformation
                )
                stats.add(result)
                
                await request.watcherState.updateActiveTrade(nil)
            } else if isTradeExitEnabled {
                guard let account = marketOrder?.account else { return }
                guard let position = account.positions.first(where: { $0.label == contract.label }) else { return }

                do {
                    try await marketOrder?.makeLimitOrder(
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
