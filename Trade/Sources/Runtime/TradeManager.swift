import Foundation
import Brokerage
import Persistence
import NIOConcurrencyHelpers
import TradingStrategy
import OrderedCollections

@Observable public class TradeManager: @unchecked Sendable {
    private let lock: NIOLock = NIOLock()
    
    public let market: Market
    public let persistance: Persistence
    public let fileProvider: MarketDataFileProvider
    public let tradeAlertHandler: TradeAlertHandling?
    public private(set) var watchers: [String: Watcher] = [:]
    
    public var selectedWatcher: String?
    private var isLookingUpSuggestions: Bool = false
    private var annoucments: [Annoucment] = []
    
    
    public var watcher: Watcher? {
        guard let id = selectedWatcher else { return nil }
        return lock.withLock {
            return watchers[id]
        }
    }
    
    public func removeAllWatchers() {
        lock.withLock {
            watchers.removeAll()
        }
    }
    
    public func removeWatcher(_ id: String) {
        lock.withLock {
            watchers[id] = nil
        }
    }
    
    public func watchersGroups() -> OrderedDictionary<TradeAggregator, [Watcher]> {
        return lock.withLock {
            var groupedWatchers: OrderedDictionary<TradeAggregator, [Watcher]> = OrderedDictionary(grouping: watchers.values) { $0.tradeAggregator }
            
            for (aggregator, watchers) in groupedWatchers {
                groupedWatchers[aggregator] = watchers.sorted { lhs, rhs in
                    if lhs.contract.type != rhs.contract.type {
                        return lhs.contract.type < rhs.contract.type
                    }
                    if lhs.contract.exchangeId != rhs.contract.exchangeId {
                        return lhs.contract.exchangeId < rhs.contract.exchangeId
                    }
                    if lhs.contract.symbol != rhs.contract.symbol {
                        return lhs.contract.symbol < rhs.contract.symbol
                    }
                    return lhs.interval < rhs.interval
                }
            }
            
            let sortedGroupedWatchers = OrderedDictionary(
                uniqueKeysWithValues: groupedWatchers.sorted(by: { $0.key.id < $1.key.id })
            )
            return sortedGroupedWatchers
        }
    }
    
    public init(
        market: Market = InteractiveBrokers(),
        persistance: Persistence = PersistenceManager(),
        fileProvider: MarketDataFileProvider = MarketDataFileProvider(),
        tradeAlertHandler: TradeAlertHandling?
    ) {
        self.market = market
        self.persistance = persistance
        self.fileProvider = fileProvider
        self.tradeAlertHandler = tradeAlertHandler
    }
    
    public func initializeSockets() {
        Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
                try await market.connect()
            } catch {
                print("initializeSockets failed with error: ", error)
            }
        }
    }
    
    // MARK: - Market Data
    
    public func cancelMarketData(_ asset: Asset) async throws {
        try await market.unsubscribeMarketData(contract: asset.instrument, interval: asset.interval)
        let id = asset.id
        await MainActor.run { [id] in
            lock.withLockVoid {
                watchers.removeValue(forKey: id)
            }
        }
    }
    
    @MainActor
    public func marketData<T: Strategy>(
        contract: any Contract,
        interval: TimeInterval,
        strategyType: T.Type
    ) throws {
        let assetId = "\(strategyType.id)\(contract.label):\(interval)"
        try lock.withLockVoid {
            guard watchers[assetId] == nil else {
                print("🔴 Watcher already exist for strategy: \(strategyType.name), strategy type:", String(describing: strategyType))
                return
            }
            let agregator = TradeAggregator(
                contract: contract,
                marketOrder: market,
                getNextTradingAlertsAction: { [weak self] in
                    guard let self else { return nil }
                    return nextAnnoucment(in: annoucments)
                },
                tradeEntryNotificationAction: { [weak self] (trade, recentBar) in
                    self?.tradeAlertHandler?.sendAlert(trade, recentBar: recentBar)
                },
                tradeExitNotificationAction: { [weak self] (trade, recentBar) in
                    self?.tradeAlertHandler?.sendAlert(trade, recentBar: recentBar)
                },
                patternInformationChangeAction: { [weak self] patternInformation in
                    self?.tradeAlertHandler?.patternInformationChange(patternInformation)
                }
            )
            let watcher = try Watcher(
                contract: contract,
                interval: interval,
                strategyType: strategyType,
                tradeAggregator: agregator,
                market: market,
                fileProvider: fileProvider
            )
            watchers[assetId] = watcher
        }
    }
    
    public func updateAnnoucments(_ annoucments: [Annoucment]) {
        self.annoucments = annoucments
    }
    
    private func nextAnnoucment(after time: TimeInterval = Date().timeIntervalSince1970, in annoucments: [Annoucment]) -> Annoucment? {
        annoucments
            .filter { $0.timestamp > time }
            .sorted { $0.timestamp < $1.timestamp }
            .first
    }

    
    // MARK: Load Dylibs Files and its Strategies
    
    func loadAvailableStrategies(from path: String) -> [String] {
        let handle = dlopen(path, RTLD_NOW)
        guard handle != nil else {
            print("❌ Failed to open \(path)")
            return []
        }

        guard let symbol = dlsym(handle, "getAvailableStrategies") else {
            print("❌ Failed to find `getAvailableStrategies` symbol in \(path)")
            return []
        }

        typealias GetAvailableStrategiesFunc = @convention(c) () -> UnsafePointer<CChar>
        let function = unsafeBitCast(symbol, to: GetAvailableStrategiesFunc.self)

        let strategyPointer = function()
        let strategyList = String(cString: strategyPointer)

        free(UnsafeMutablePointer(mutating: strategyPointer))

        return strategyList.components(separatedBy: ",")
    }

    func loadStrategy(from path: String, strategyName: String) -> Strategy.Type? {
        let handle = dlopen(path, RTLD_NOW)
        guard handle != nil else {
            print("❌ Failed to open \(path): \(String(cString: dlerror()!))")
            return nil
        }

        guard let symbol = dlsym(handle, "createStrategy") else {
            print("❌ Failed to find `createStrategy` symbol in \(path): \(String(cString: dlerror()!))")
            return nil
        }

        typealias CreateStrategyFunc = @convention(c) (UnsafePointer<CChar>) -> UnsafeRawPointer?
        let function = unsafeBitCast(symbol, to: CreateStrategyFunc.self)
        guard let strategyPointer = function(strategyName) else {
            print("❌ `createStrategy()` returned nil")
            return nil
        }

        let factoryBox = Unmanaged<Box<() -> Strategy>>.fromOpaque(strategyPointer).takeRetainedValue()
        let strategyInstance = factoryBox.value()
        let strategyType = type(of: strategyInstance)
        return strategyType
    }

    @MainActor
    public func loadAllUserStrategies(into registry: StrategyRegistry, location strategyFolder: String) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: strategyFolder) else {
            return
        }

#if os(Linux)
        let extensionSuffix = ".so"
#else
        let extensionSuffix = ".dylib"
#endif
        
        for file in files where file.hasSuffix(extensionSuffix) {
            let url = URL(fileURLWithPath: strategyFolder).appendingPathComponent(file)
            loadStrategy(into: registry, location: url.path())
        }
        // Only register DoNothingStrategy as it's the only strategy that actually exists in the codebase
        registry.register(strategyType: DoNothingStrategy.self)
    }
    
    @MainActor
    public func loadStrategy(into registry: StrategyRegistry, location fullPath: String) {
        let strategyNames = loadAvailableStrategies(from: fullPath)
        print("🔵 loading: ", strategyNames, fullPath)
        for strategyName in strategyNames {
            if let strategyType = loadStrategy(from: fullPath, strategyName: strategyName) {
                registry.register(strategyType: strategyType)
                print("✅ Successfully registered strategy: \(strategyName)")
            } else {
                print("❌ Failed to load strategy: \(strategyName)")
            }
        }
    }
    
    // MARK: Types
    
    private final class Box<T> {
        let value: T
        init(_ value: T) { self.value = value }
    }
}
