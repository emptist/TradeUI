import Foundation
import OrderedCollections
import Brokerage
import Persistence
import TradingStrategy
import SwiftUI

public final class Watcher: @unchecked Sendable, Identifiable {
    public private(set) var contract: any Contract
    public private(set) var interval: TimeInterval
    public private(set) var watcherState: WatcherStateActor
    
    private let userInfo: [String: Any]
    private var maxCandlesCount: Int {
        let targetIntervals: [TimeInterval] = [900.0, 3600.0, 7200.0]
        let multiplier = targetIntervals.first(where: { $0 > interval }).map { Int($0 / interval) } ?? 1
        return 200 * multiplier
    }
    
    public let isSimulation: Bool
    public var symbol: String { contract.symbol }
    public var id: String { "\(strategyType.id)\(contract.label):\(interval)" }
    public var displayName: String { "\(symbol): \(interval.formatCandleTimeInterval())" }
    public let strategyType: Strategy.Type
    public var tradeAggregator: TradeAggregator!
        
    private var quoteTask: Task<Void, Never>?
    private var marketDataTask: Task<Void, Never>?
    private var tradeTask: Task<Void, Never>?
    private var fileData: MarketDataFileProvider?
    public var pullNext: Double = .greatestFiniteMagnitude {
        didSet {
            guard oldValue == 0, pullNext > 0 else { return }
            pull()
        }
    }
    
    deinit {
        tradeAggregator = nil
        quoteTask?.cancel()
        quoteTask = nil
        marketDataTask?.cancel()
        marketDataTask = nil
        tradeTask?.cancel()
        tradeTask = nil
    }

    public init(
        contract: any Contract,
        interval: TimeInterval,
        strategyType: Strategy.Type,
        tradeAggregator: TradeAggregator,
        marketData: MarketData,
        fileProvider: CandleFileProvider,
        userInfo: [String: Any] = [:]
    ) throws {
        self.contract = contract
        self.interval = interval
        self.userInfo = userInfo
        self.strategyType = strategyType
        self.tradeAggregator = tradeAggregator
        self.fileData = marketData as? MarketDataFileProvider
        self.isSimulation = marketData is MarketDataFileProvider
        self.watcherState = WatcherStateActor(initialStrategy: strategyType.init(candles: []))
        
        reconnectToLiveFeed(using: marketData, fileProvider: fileProvider)
        fetchTredingHours(marketData: marketData)
    }
    
    public convenience init(
        contract: any Contract,
        interval: TimeInterval,
        strategyType: Strategy.Type,
        tradeAggregator: TradeAggregator,
        market: Market,
        fileProvider: CandleFileProvider,
        userInfo: [String: Any] = [:]
    ) throws {
        try self.init(
            contract: contract,
            interval: interval,
            strategyType: strategyType,
            tradeAggregator: tradeAggregator,
            marketData: market,
            fileProvider: fileProvider,
            userInfo: userInfo
        )
    }
    
    public convenience init(
        contract: any Contract,
        interval: TimeInterval,
        strategyType: Strategy.Type,
        tradeAggregator: TradeAggregator,
        fileProvider: CandleFileProvider & MarketData,
        userInfo: [String: Any] = [:]
    ) throws {
        try self.init(
            contract: contract,
            interval: interval,
            strategyType: strategyType,
            tradeAggregator: tradeAggregator,
            marketData: fileProvider,
            fileProvider: fileProvider,
            userInfo: userInfo
        )
    }
    
    public func disconnectFromLiveFeed() async {
        quoteTask?.cancel()
        marketDataTask?.cancel()
        tradeTask?.cancel()
        quoteTask = nil
        marketDataTask = nil
        tradeTask = nil
    }
    
    public func reconnectToLiveFeed(using marketData: MarketData, fileProvider: CandleFileProvider) {
        quoteTask?.cancel()
        marketDataTask?.cancel()
        
        self.quoteTask = Task { [weak self, marketData] in
            guard let self else { return }
            await self.setupMarketQuoteData(market: marketData)
        }
        self.marketDataTask = Task { [weak self, marketData] in
            guard let self else { return }
            await self.setupMarketData(marketData: marketData, fileProvider: fileProvider)
        }
    }
    
    public func switchToHistorical(start: Date, end: Date, using marketData: MarketData) async {
        await disconnectFromLiveFeed()
        Task {
            do {
                let stream = try marketData.marketDataSnapshot(
                    contract: contract,
                    interval: interval,
                    startDate: start,
                    endDate: end,
                    userInfo: userInfo
                )
                for await candlesData in stream {
                    let newStrategy = updateStrategy(bars: candlesData.bars)
                    await watcherState.updateStrategy(newStrategy)
                }
            } catch {
                print("⚠️ Failed to fetch historical data: \(error)")
            }
        }
    }
    
    public func saveCandles(fileProvider: CandleFileProvider) {
        Task { [fileProvider] in
            let strategy = await watcherState.getStrategy()
            guard !strategy.candles.isEmpty else { return }
            snapshotData(fileProvider: fileProvider, candles: strategy.candles)
        }
    }
    
    public func fetchTredingHours(marketData: MarketData) {
        Task { [marketData] in
            let hours = try await marketData.tradingHour(contract)
            await watcherState.updateTradingHours(hours)
        }
    }
    
    private func setupMarketQuoteData(market: MarketData) async {
        do {
            for await newQuote in try market.quotePublisher(contract: contract) {
                var latestQuote: Quote?
                let quote = await watcherState.getQuote()
                if var existingQuote = latestQuote ?? quote {
                    switch newQuote.type {
                    case .bidPrice: existingQuote.bidPrice = newQuote.value
                    case .askPrice: existingQuote.askPrice = newQuote.value
                    case .lastPrice: existingQuote.lastPrice = newQuote.value
                    case .volume: existingQuote.volume = newQuote.value
                    case .none: break
                    }
                    existingQuote.date = Date()
                    latestQuote = existingQuote
                } else {
                    latestQuote = Quote(
                        contract: contract,
                        date: Date(),
                        bidPrice: newQuote.type == .bidPrice ? newQuote.value : nil,
                        askPrice: newQuote.type == .askPrice ? newQuote.value : nil,
                        lastPrice: newQuote.type == .lastPrice ? newQuote.value : nil,
                        volume: newQuote.type == .volume ? newQuote.value : nil
                    )
                }
                if let updatedQuote = latestQuote {
                    await watcherState.updateQuote(updatedQuote)
                }
            }
        } catch {
            print("Quote stream error: \(error)")
        }
    }
    
    func setupMarketData(marketData: MarketData, fileProvider: CandleFileProvider) async {
        do {
            var updatedUserInfo = userInfo
            updatedUserInfo[MarketDataKey.bufferInfo.rawValue] = interval * Double(maxCandlesCount) * 2.0
            
            for await candlesData in try marketData.marketData(
                contract: contract,
                interval: interval,
                userInfo: updatedUserInfo
            ) {
                if Task.isCancelled { break }
                let isSimulation = marketData is MarketDataFileProvider
                let bars = await updateBars(candlesData.bars, isSimulation: isSimulation)
                let newStrategy = updateStrategy(bars: bars)
                
                await watcherState.updateStrategy(newStrategy)
                let oldCount = self.tradeAggregator.activeSimulationTrades.count
                await tradeAggregator?.registerTradeSignal(
                    TradeAggregator.Request(
                        isSimulation: isSimulation,
                        watcherState: watcherState,
                        contract: contract,
                        interval: interval
                    )
                )
//                if newStrategy.patternIdentified != nil,
//                   oldCount < self.tradeAggregator.activeSimulationTrades.count {
//                    pullNext = 0
//                }
                if pullNext > 0 {
                    if let fileData = marketData as? MarketDataFileProvider,
                       let url = userInfo[MarketDataKey.snapshotFileURL.rawValue] as? URL {
                        await fileData.pull(url: url)
                    }
                }
            }
            print("-- END --")
            print("active trades", self.tradeAggregator.activeSimulationTrades.count)
            self.tradeAggregator.stats.printStats(isEnd: true)
        } catch {
            print("Market data stream error: \(error)")
        }
    }
    
    private func pull() {
        pullNext -= 1
        if let fileData, let url = userInfo[MarketDataKey.snapshotFileURL.rawValue] as? URL {
            Task {
                await fileData.pull(url: url)
            }
        }
    }
    
    private func snapshotData(fileProvider: CandleFileProvider, candles: [any Klines]) {
        guard let bars = candles as? [Bar] else { return }
        do {
            try fileProvider.save(
                symbol: contract.symbol,
                interval: interval,
                bars: bars,
                strategyName: String(describing: strategyType)
            )
        } catch {
            print("🔴 Failed to save snapshot data for:", id)
        }
    }
    
    private func updateBars(_ bars: [Bar], isSimulation: Bool) async -> [Bar] {
        let strategy = await watcherState.getStrategy()
        var currentCandles = OrderedSet(strategy.candles as? [Bar] ?? [])
        if currentCandles.isEmpty {
            currentCandles = OrderedSet(bars)
        } else {
            for bar in bars {
                if let index = currentCandles.lastIndex(of: bar) {
                    currentCandles.update(bar, at: index)
                } else if let lastBar = currentCandles.last, bar.timeOpen >= (lastBar.timeOpen + interval) {
                    currentCandles.updateOrAppend(bar)
                }
            }
        }
        if currentCandles.count > maxCandlesCount {
            currentCandles.removeFirst(currentCandles.count - maxCandlesCount)
        }
        return Array(currentCandles)
    }
    
    private func updateStrategy(bars: [Bar]) -> any Strategy {
        strategyType.init(candles: bars)
    }
    
    // MARK: - Types
    
    public enum DataMode: Hashable {
        case live
        case historical(start: Date, end: Date)
    }
    
    public actor WatcherStateActor {
        private var quote: Quote?
        private var strategy: Strategy
        private var tradingHours: [TradingHour] = []
        
        init(initialStrategy: Strategy) {
            self.strategy = initialStrategy
        }
        
        public func updateQuote(_ newQuote: Quote) {
            self.quote = newQuote
        }
        
        public func getQuote() -> Quote? {
            return quote
        }
        
        public func getStrategy() -> Strategy {
            return strategy
        }
        
        public func updateStrategy(_ newStrategy: Strategy) {
            self.strategy = newStrategy
        }
    
        public func updateTradingHours(_ tradingHours: [TradingHour]) {
            self.tradingHours = tradingHours
        }
        
        public func getTradingHours() -> [TradingHour]? {
            return tradingHours
        }
    }
}

// MARK: Helpers

extension Bar: Klines {}

extension TimeInterval {
    func formatCandleTimeInterval() -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        switch self {
        case 60...3599:
            formatter.allowedUnits = [.minute]
        case 3600...86399:
            formatter.allowedUnits = [.hour]
        case 86400...604799:
            formatter.allowedUnits = [.day]
        case 604800...:
            formatter.allowedUnits = [.weekOfMonth]
        default:
            formatter.allowedUnits = [.second]
        }
        return formatter.string(from: self) ?? "N/A"
    }
}

// Persistance Candle
extension Candle {
    init (from data: any Klines) {
        self.init(
            timeOpen: data.timeOpen,
            interval: data.interval,
            priceOpen: data.priceOpen,
            priceHigh: data.priceHigh,
            priceLow: data.priceLow,
            priceClose: data.priceClose,
            volume: data.volume
        )
    }
}
