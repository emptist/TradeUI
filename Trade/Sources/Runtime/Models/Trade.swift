import Foundation
import TradingStrategy

public struct Trade: Sendable {
    public var entryBar: Klines
    public var price: Double
    public var targets: (takeProfit: Double?, stopLoss: Double?)
    public var units: Double
    public var signal: Signal
    public var patternInformation: [String: Double]
    
    public var isLong: Bool {
        switch signal {
        case .buy: true
        case .sell: false
        }
    }
    
    public init(
        entryBar: Klines,
        signal: Signal,
        price: Double,
        targets: (takeProfit: Double?, stopLoss: Double?),
        units: Double,
        patternInformation: [String: Double]
    ) {
        self.entryBar = entryBar
        self.price = price
        self.targets = targets
        self.units = units
        self.signal = signal
        self.patternInformation = patternInformation
    }
}
