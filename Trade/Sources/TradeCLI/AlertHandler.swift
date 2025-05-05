import Runtime
import TradingStrategy
import Foundation

struct AlertHandler: TradeAlertHandling, Sendable {
    func patternInformationChange(_ patternInformation: [String: Bool]) {
        let patterns = patternInformation.map { (pattern, active) in
            "\(active ? "✅" : "❌") \(pattern): \(active ? "Active" : "Inactive")"
        }.joined(separator: "\n│ ")
        
        print("""
                📊 Strategy Update
                ┌──────────────────────────────┐
                │ Patterns:                    │
                │ \(patterns)
                └──────────────────────────────┘
                """)
    }
    
    func sendAlert(_ trade: Runtime.Trade, recentBar: any TradingStrategy.Klines) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        
        let entryTime = dateFormatter.string(from: Date(timeIntervalSince1970: trade.entryBar.timeOpen))
        let recentTime = dateFormatter.string(from: Date(timeIntervalSince1970: recentBar.timeOpen))
        let volumeInfo = recentBar.volume != nil ? String(format: "%.2f", recentBar.volume!) : "N/A"
        
        // Check if it's an entry or exit alert
        let isEntry = (trade.entryBar.timeOpen == recentBar.timeOpen && trade.entryBar.priceOpen == recentBar.priceOpen)
        
        if isEntry {
            // Trade Entry Alert
            print("""
            🚀 Trade Entry Alert 🚀
            ┌──────────────────────────────┐
            │ Trade Initiated              │
            ├──────────────────────────────┤
            │ Entry Time: \(entryTime)
            │ Entry Price: $\(String(format: "%.2f", trade.price))
            │ Trail Stop Price: $\(String(format: "%.2f", trade.stopPrice))
            │ Units: \(String(format: "%.2f", trade.units))
            │ Direction: \(trade.isLong ? "Long" : "Short")
            └──────────────────────────────┘
            ┌──────────────────────────────┐
            │ Entry Bar (Interval: \(String(format: "%.0f", recentBar.interval))s) │
            ├──────────────────────────────┤
            │ Open: $\(String(format: "%.2f", recentBar.priceOpen))
            │ High: $\(String(format: "%.2f", recentBar.priceHigh))
            │ Low: $\(String(format: "%.2f", recentBar.priceLow))
            │ Close: $\(String(format: "%.2f", recentBar.priceClose))
            │ Volume: \(volumeInfo)
            └──────────────────────────────┘
            """)
        } else {
            // Trade Exit Alert
            let profit = trade.isLong
                ? recentBar.priceClose - trade.price
                : trade.price - recentBar.priceClose
            let didHitStopLoss = trade.isLong
                ? recentBar.priceClose <= trade.stopPrice
                : recentBar.priceClose >= trade.stopPrice
            
            print("""
            🛑 Trade Exit Alert 🛑
            ┌──────────────────────────────┐
            │ Trade Closed                 │
            ├──────────────────────────────┤
            │ Entry Time: \(entryTime)
            │ Entry Price: $\(String(format: "%.2f", trade.price))
            │ Exit Time: \(recentTime)
            │ Exit Price: $\(String(format: "%.2f", recentBar.priceClose))
            │ Profit: $\(String(format: "%.2f", profit))
            │ Did Hit Stop Loss: \(didHitStopLoss ? "Yes" : "No")
            │ Units: \(String(format: "%.2f", trade.units))
            │ Direction: \(trade.isLong ? "Long" : "Short")
            └──────────────────────────────┘
            ┌──────────────────────────────┐
            │ Exit Bar (Interval: \(String(format: "%.0f", recentBar.interval))s) │
            ├──────────────────────────────┤
            │ Open: $\(String(format: "%.2f", recentBar.priceOpen))
            │ High: $\(String(format: "%.2f", recentBar.priceHigh))
            │ Low: $\(String(format: "%.2f", recentBar.priceLow))
            │ Close: $\(String(format: "%.2f", recentBar.priceClose))
            │ Volume: \(volumeInfo)
            └──────────────────────────────┘
            """)
        }
    }
}
