import Foundation

public protocol MarketDataFile {
    var fileUrl: URL { get }
    
    func readBars(symbol: Symbol, interval: TimeInterval, loadAllAtOnce: Bool) throws -> AsyncStream<CandleData>
    func save(strategyName: String, candleData: CandleData)
    func loadCandleData() -> CandleData?
    // Notify data provider, client is ready for another signal
    func publish()
    func close()
}
