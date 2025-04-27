import Foundation
import TradingStrategy

public struct Trade: Sendable {
    public var entryBar: Klines
    public var price: Double
    public var stopPrice: Double
    public var units: Double
    
    public init(entryBar: Klines, price: Double, stopPrice: Double, units: Double) {
        self.entryBar = entryBar
        self.price = price
        self.stopPrice = stopPrice
        self.units = units
    }
}
