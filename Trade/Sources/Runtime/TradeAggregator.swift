// MARK: - TradeAggregator.swift

import Foundation
import Brokerage
import TradingStrategy

public final class TradeAggregator: Hashable {
    public var isTradeEntryEnabled = true
    public var isTradeExitEnabled = true
    public var isTradeEntryNotificationEnabled = true
    public var isTradeExitNotificationEnabled = true
    public var minConfirmations = 1

    public let id = UUID()
    public let contract: any Contract

    private var marketOrder: MarketOrder?
    private var tradeSignals: Set<Request> = []
    private var activeSimulationTrades: [UUID: Trade] = [:]
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
        self.contract = contract
        self.marketOrder = marketOrder
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

        guard let _ = strategy.patternIdentified else {
            tradeQueue.sync(flags: .barrier) { _ = tradeSignals.remove(request) }
            return
        }
         
        guard
            let timeRemaining = strategy.candles.last?.timeRemaining,
            (timeRemaining < 5.0 && timeRemaining > 0) || request.isSimulation
        else {
            tradeQueue.sync(flags: .barrier) { _ = tradeSignals.remove(request) }
            return
        }

        let alignedRequests = await alignedTradeRequests(request)
        let (confirmedSignal, matchingRequests) = majorityVote(alignedRequests)

        guard
            let signal = confirmedSignal,
            matchingRequests.count >= minConfirmations
        else {
            print("⏳ Waiting for confirmations: \(tradeSignals.count)/\(minConfirmations)")
            return
        }

        let avgConfidence = matchingRequests.compactMap { $0.1?.confidence }.reduce(0, +) / Float(matchingRequests.count)
        guard avgConfidence > 0 else {
            print("⚠️ Low confidence: \(avgConfidence)")
            return
        }

        let matchingRequest = tradeQueue.sync(flags: .barrier) {
            let match = tradeSignals.first { $0.contract.label == contract.label }
            if match != nil { tradeSignals.removeAll() }
            return match
        }

        guard let requestToTrade = matchingRequest else {
            print("🔴 No matching request")
            return
        }

        await enterTradeIfStrategyIsValidated(requestToTrade, signal: signal)

        tradeQueue.sync(flags: .barrier) {
            tradeSignals = []
        }

        await manageActiveTrade(request)
    }
    
    public func placeManualTrade(from watcher: Watcher, isLong: Bool) async {
        let strategy = await watcher.watcherState.getStrategy()
        guard let entryBar = strategy.candles.last else {
            print("❌ No bar available for manual trade.")
            return
        }

        let signal: Signal = isLong ? .buy(confidence: 1) : .sell(confidence: 1)
        let targets = strategy.exitTargets(for: signal, entryBar: entryBar)

        let trade = Trade(
            entryBar: entryBar,
            signal: signal,
            price: entryBar.priceClose,
            targets: targets,
            units: 1.0,
            patternInformation: strategy.patternInformation
        )
        await evaluateMarketCoonditions(
            trade: trade,
            request: Request(
                isSimulation: false,
                watcherState: watcher.watcherState,
                contract: contract,
                interval: entryBar.interval
            )
        )
    }
}

// MARK: - Entry Logic

private extension TradeAggregator {
    func alignedTradeRequests(_ request: Request) async -> [(Request, Signal?)] {
        await tradeQueue.sync(flags: .barrier) {
            tradeSignals.insert(request)
            return Array(tradeSignals)
        }.asyncMap { req async in
            let sig = await req.watcherState.getStrategy().patternIdentified
            return (req, sig)
        }
    }

    func majorityVote(_ requests: [(Request, Signal?)]) -> (Signal?, [(Request, Signal?)]) {
        let grouped = Dictionary(grouping: requests, by: { $0.1 })
        return grouped.filter { $0.key != nil }
            .max { $0.value.count < $1.value.count } ?? (nil, [])
    }

    func enterTradeIfStrategyIsValidated(_ request: Request, signal: Signal) async {
        guard !Task.isCancelled else { return }

        let strategy = await request.watcherState.getStrategy()
        guard let entryBar = strategy.candles.last else { return }
        let details = await request.watcherState.getTradingHours()?.first
        let targets = strategy.exitTargets(for: signal, entryBar: entryBar)
        let units = strategy.shouldEnterWitUnitCount(
            signal: signal,
            entryBar: entryBar,
            equity: request.isSimulation ? 1_000_000 : (marketOrder?.account?.buyingPower ?? 0),
            tickValue: details?.tickValue ?? 1,
            tickSize: details?.tickSize ?? 1,
            feePerUnit: 10,
            nextAnnoucment: request.isSimulation ? nil : getNextTradingAlertsAction?()
        )

        guard units > 0 else { return }

        let trade = Trade(
            entryBar: entryBar,
            signal: signal,
            price: entryBar.priceClose,
            targets: targets,
            units: Double(units),
            patternInformation: strategy.patternInformation
        )

        if request.isSimulation {
            activeSimulationTrades[trade.id] = trade
        } else {
            await evaluateMarketCoonditions(trade: trade, request: request)
        }
    }
}

// MARK: - Position Management

private extension TradeAggregator {
    func evaluateMarketCoonditions(trade: Trade, request: Request) async {
        let marketOpen = await request.watcherState.getTradingHours()?.isMarketOpen()
        
        guard
            let marketOpen,
            marketOpen.isOpen,
            let timeUntilClose = marketOpen.timeUntilChange,
            timeUntilClose > (1_800 * 6)
        else {
            print("⚠️ Market closed.")
            return
        }
        
        guard
            let quote = await request.watcherState.getQuote()
        else {
            print("⚠️ Market quote missing.")
            return
        }
        let price = determineOrderPrice(signal: trade.signal, quote: quote, fallback: trade.price)
        let finalTrade = Trade(
            id: trade.id,
            entryBar: trade.entryBar,
            signal: trade.signal,
            price: price,
            targets: trade.targets,
            units: trade.units,
            patternInformation: trade.patternInformation
        )

        if isTradeEntryNotificationEnabled {
            tradeEntryNotificationAction?(finalTrade, finalTrade.entryBar)
        }

        guard isTradeEntryEnabled else { return }

        do {
            try await placeOrder(trade: finalTrade, isLong: finalTrade.isLong)
        } catch {
            print("🔴 Order failed: \(error)")
        }
    }

    func determineOrderPrice(signal: Signal, quote: Quote, fallback: Double) -> Double {
        if signal.isLong { return quote.askPrice ?? fallback }
        else { return quote.bidPrice ?? fallback }
    }

    func placeOrder(trade: Trade, isLong: Bool) async throws {
        guard let order = marketOrder else { return }
        let action: OrderAction = isLong ? .buy : .sell
        try await order.makeLimitWithStopOrder(
            contract: contract,
            action: action,
            price: trade.price,
            targets: trade.targets,
            quantity: trade.units
        )
    }

    func manageActiveTrade(_ request: Request) async {
        guard !Task.isCancelled else { return }
        let strategy = await request.watcherState.getStrategy()
        guard let recentBar = strategy.candles.last else { return }

        if request.isSimulation {
            await manageSimulation(request, recentBar: recentBar)
        } else {
            // TODO: Add dynamic should exit handling
        }
    }
    
    private func manageSimulation(_ request: Request, recentBar: any Klines) async {
        for trade in activeSimulationTrades.values {
            let isLong = trade.isLong

            let hitStop = isLong
                ? recentBar.priceLow <= (trade.targets.stopLoss ?? .infinity)
                : recentBar.priceHigh >= (trade.targets.stopLoss ?? -.infinity)

            let hitProfit = isLong
                ? recentBar.priceHigh >= (trade.targets.takeProfit ?? .infinity)
                : recentBar.priceLow <= (trade.targets.takeProfit ?? -.infinity)

            if hitStop || hitProfit {
                let price = (await request.watcherState.getQuote())?.lastPrice ?? recentBar.priceClose
                let result = TradeResult(
                    entryTime: trade.entryBar.timeOpen,
                    exitTime: recentBar.timeOpen,
                    isLong: isLong,
                    entryPrice: trade.price,
                    exitPrice: price,
                    profit: isLong ? price - trade.price : trade.price - price,
                    targets: (hitProfit, hitStop),
                    confidence: trade.signal.confidence,
                    patternInformation: trade.patternInformation
                )
                stats.add(result)
                
                activeSimulationTrades[trade.id] = nil
            }
        }
    }
}

// MARK: - Helpers

public extension TradeAggregator {
    struct Request: Hashable {
        let isSimulation: Bool
        let watcherState: Watcher.WatcherStateActor
        let contract: any Contract
        let interval: TimeInterval

        public func hash(into hasher: inout Hasher) {
            hasher.combine(contract.label)
            hasher.combine(interval)
        }

        public static func == (lhs: Request, rhs: Request) -> Bool {
            lhs.contract.label == rhs.contract.label && lhs.interval == rhs.interval
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(contract.label)
        hasher.combine(id)
    }

    static func == (lhs: TradeAggregator, rhs: TradeAggregator) -> Bool {
        lhs.id == rhs.id
    }
}

public extension TradeAggregator.Request {
    var symbol: String { contract.symbol }
}
