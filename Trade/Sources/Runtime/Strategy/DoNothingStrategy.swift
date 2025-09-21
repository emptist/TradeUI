import Foundation
import TradingStrategy

public struct DoNothingStrategy: Strategy, Versioned {
    public static let id = "com.view.only"
    public static let name = "Viewing only"
    public static let description: String = "A strategy that doesn't execute any trades"
    
    // Conformance to Versioned protocol
    public static let version: String = "1.0.0"
    
    public let charts: [[Klines]]
    public let levels: [Level]
    public let patterns: [(index: Int, pattern: PricePattern)] = []
    public let distribution: [[Phase]]
    public let indicators: [[String: [Double]]]
    public let resolution: [Scale]
    
    public init(candles: [Klines]) {
        let interval = candles.first?.interval ?? 60
        let totalTradingSeconds = 8 * 3600.0
        let candleCount = Int(totalTradingSeconds / interval)
        let scale = Scale(data: candles, candlesPerScreen: candleCount)
        
        self.charts = [candles]
        self.resolution = [scale]
        self.indicators = [[:]]
        self.levels = []
        self.distribution = []
    }

    public var patternIdentified: Signal? {
        return nil
    }
    
    public var patternInformation: [String: Double] {
        return [:]
    }

    // MARK: - Position Manager & Trade Decision

    public func shouldEnterWitUnitCount(
        signal: Signal,
        entryBar: Klines,
        equity: Double,
        tickValue: Double,
        tickSize: Double,
        feePerUnit cost: Double,
        nextAnnouncment annoucment: Annoucment?
    ) -> Int {
        return 0
    }
    
    public func shouldExit(signal: Signal, entryBar: Klines, nextAnnouncment annoucment: Annoucment?) -> Bool {
        return true
    }
    
    public func exitTargets(for signal: Signal, entryBar: Klines) -> (takeProfit: Double?, stopLoss: Double?) {
        return (nil, nil)
    }
}
