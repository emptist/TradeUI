import Foundation

public final class MarketDataFileProvider: @unchecked Sendable, MarketData {
    public enum Error: Swift.Error, LocalizedError {
        case missingDirectory(String)
        case missingFile(String)
        case wrongFileFormat(String)
    }
    
    public let snapshotsDirectory: URL?
    private var activeSubscriptions: [MarketDataFile] = []
    public var account: Account? = nil
    
    deinit {
        activeSubscriptions.forEach { $0.close() }
        activeSubscriptions.removeAll()
    }
    
    required public init() {
        let fileManager = FileManager.default
        snapshotsDirectory = try? fileManager
            .url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Snapshots")
    }
    
    public func pull(url: URL) {
        guard let file = activeSubscriptions.first(where: { $0.fileUrl == url }) else {
            return
        }
        Task {
            try await Task.sleep(for: .milliseconds(5))
            file.publish()
        }
    }
    
    public func connect() async throws {
        guard let snapshotsDirectory,
              FileManager.default.fileExists(atPath: snapshotsDirectory.path) else {
            throw Error.missingDirectory("Missing 'Snapshots' directory.")
        }
    }
    
    public func disconnect() async throws {
        activeSubscriptions.forEach { $0.close() }
        activeSubscriptions.removeAll()
    }
    
    public func unsubscribeMarketData(contract: any Contract, interval: TimeInterval) {
        activeSubscriptions.removeAll {
            $0.fileUrl.lastPathComponent.contains(contract.symbol)
        }
    }

    public func quotePublisher(contract product: any Contract) throws -> AsyncStream<Quote> {
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func marketDataSnapshot(
        contract product: any Contract,
        interval: TimeInterval,
        startDate: Date,
        endDate: Date?,
        userInfo: [String: Any]
    ) throws -> AsyncStream<CandleData> {
        guard let url = userInfo[MarketDataKey.snapshotFileURL.rawValue] as? URL else {
            throw Error.missingFile("File URL missing in user info")
        }
        
        return AsyncStream { continuation in
            do {
                let candleData = try loadFileData(url: url, symbol: product.symbol, interval: interval)
                continuation.yield(candleData ?? CandleData(symbol: product.symbol, interval: interval, bars: []))
            } catch {
                print("❌ Error loading snapshot: \(error)")
            }
            continuation.finish()
        }
    }

    public func marketData(
        contract product: any Contract,
        interval: TimeInterval,
        userInfo: [String: Any]
    ) throws -> AsyncStream<CandleData> {
        guard let fileURL = userInfo[MarketDataKey.snapshotFileURL.rawValue] as? URL else {
            throw Error.missingFile("File URL missing in user info")
        }
        
        let marketDataFile = try marketDataFile(fileURL)
        activeSubscriptions.append(marketDataFile)
        
        return try marketDataFile.readBars(symbol: product.symbol, interval: interval, loadAllAtOnce: false)
    }

    public func tradingHour(_ product: any Contract) async throws -> [TradingHour] {
        return []
    }

    public func save(symbol: Symbol, interval: TimeInterval, bars: [Bar], strategyName strategy: String) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MMM-yyyy_HH-mm-ss"
        let fileName = "\(symbol)-\(interval)_\(dateFormatter.string(from: Date()))"
        let marketDataFile = try marketDataFile(marketDataFileURL(fileName))
        marketDataFile.save(strategyName: strategy, candleData: CandleData(symbol: symbol, interval: interval, bars: bars))
    }

    public func loadFile(url: URL) throws -> CandleData? {
        try marketDataFile(url).loadCandleData()
    }

    public func loadFileData(url: URL, symbol: Symbol, interval: TimeInterval) throws -> CandleData? {
        try marketDataFile(url).loadCandleData()
    }

    private func marketDataFile(_ url: URL) throws -> MarketDataFile {
        if let file = activeSubscriptions.first(where: { $0.fileUrl == url }) {
            return file
        }
        var url = url
        let file: MarketDataFile
        switch url.pathExtension {
        case "txt":
            file = KlineMarketDataFile(fileUrl: url)
        case "csv":
            file = CSVMarketDataFile(fileUrl: url)
        default:
            url.appendPathExtension("txt")
            file = KlineMarketDataFile(fileUrl: url)
        }
        return file
    }

    private func marketDataFileURL(_ name: String) throws -> URL {
        guard let snapshotsDirectory else {
            throw Error.missingDirectory("Failed to initiate directory.")
        }
        var fileURL = snapshotsDirectory.appendingPathComponent(name)
        if fileURL.pathExtension.isEmpty {
            fileURL.appendPathExtension("txt")
        }
        return fileURL
    }
}
