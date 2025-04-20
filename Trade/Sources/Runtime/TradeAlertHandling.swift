import TradingStrategy

public protocol TradeAlertHandling: Sendable {
    func sendAlert(_ trade: Trade, recentBar: Klines)
}
