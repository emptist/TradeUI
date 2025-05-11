import Foundation
import TradingStrategy

public struct Trade: Sendable {
    public var entryBar: Klines
    public var price: Double
    public var stopPrice: Double
    public var units: Double
    public var signal: Signal
    
    public var isLong: Bool {
        switch signal {
        case .buy: true
        case .sell: false
        }
    }
    
    public init(entryBar: Klines, signal: Signal, price: Double, stopPrice: Double, units: Double) {
        self.entryBar = entryBar
        self.price = price
        self.stopPrice = stopPrice
        self.units = units
        self.signal = signal
    }
}
