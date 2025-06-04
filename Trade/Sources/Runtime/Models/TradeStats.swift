import Foundation

public struct TradeResult {
    public let entryTime: TimeInterval
    public let exitTime: TimeInterval
    public let isLong: Bool
    public let entryPrice: Double
    public let exitPrice: Double
    public let profit: Double
    public let targets: (takeProfit: Bool, stopLoss: Bool)
    public let confidence: Float
    public let patternInformation: [String: Double]
    
    public var tradeDuration: String {
        let seconds = Int(exitTime - entryTime)
        switch seconds {
        case ..<60: return "\(seconds)s ago"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3600)h ago"
        case ..<604_800: return "\(seconds / 86_400)d ago"
        default:
            if seconds < 1_000_000 {
                return String(format: "%.1fk s ago", Double(seconds) / 1_000)
            } else {
                return String(format: "%.1fM s ago", Double(seconds) / 1_000_000)
            }
        }
    }
}

public final class TradeStats {
    private(set) var results: [TradeResult] = []
    private var lastPrinted = Date()

    public var totalPnL: Double {
        results.reduce(0) { $0 + $1.profit }
    }

    public var count: Int { results.count }

    public var averageWin: Double {
        let wins = results.filter { $0.profit > 0 }
        guard !wins.isEmpty else { return 0 }
        return wins.reduce(0) { $0 + $1.profit } / Double(wins.count)
    }

    public var averageLoss: Double {
        let losses = results.filter { $0.profit < 0 }
        guard !losses.isEmpty else { return 0 }
        return losses.reduce(0) { $0 + $1.profit } / Double(losses.count)
    }

    public var winRate: Double {
        let wins = results.filter { $0.profit > 0 }
        guard !results.isEmpty else { return 0 }
        return Double(wins.count) / Double(results.count)
    }

    public var longCount: Int {
        results.filter(\.isLong).count
    }

    public var longWins: Int {
        results.filter { $0.isLong && $0.profit > 0 }.count
    }

    public var shortCount: Int {
        results.filter { !$0.isLong }.count
    }

    public var shortWins: Int {
        results.filter { !$0.isLong && $0.profit > 0 }.count
    }

    public func add(_ result: TradeResult) {
        results.append(result)
        printTrade(result)

        let now = Date()
        if results.count % 10 == 0 || now.timeIntervalSince(lastPrinted) > 10 {
            printStats()
            lastPrinted = now
        }
    }

    private func printTrade(_ result: TradeResult) {
        let direction = result.isLong ? "Long" : "Short"
        print("❌ \(direction) profit: \(result.profit) time: \(result.tradeDuration) entry: \(result.entryPrice), exit: \(result.exitPrice), targets: \(result.targets) confidence: \(result.confidence) info: \(result.patternInformation)")
    }

    public func printStats() {
        print("""
        📊 Trade Statistics:
        📊 • Trades: \(count)
        📊 • Total PnL: \(totalPnL)
        📊 • Win rate: \(String(format: "%.2f", winRate * 100))%
        📊 • Avg Win: \(averageWin)
        📊 • Avg Loss: \(averageLoss)
        📊 • Longs: \(longCount) (Wins: \(longWins))
        📊 • Shorts: \(shortCount) (Wins: \(shortWins))
        """)
    }
}
