import Foundation

public enum ExitReason {
    case stopLoss
    case takeProfit
    case momentumExit
}

public struct TradeResult {
    public let entryTime: TimeInterval
    public let exitTime: TimeInterval
    public let isLong: Bool
    public let entryPrice: Double
    public let exitPrice: Double
    public let profit: Double
    public let trade: Trade
    public let exitReason: ExitReason
    
    public var tradeDuration: String {
        let seconds = Int(exitTime - entryTime)
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        case ..<604_800: return "\(seconds / 86_400)d"
        default:
            if seconds < 1_000_000 {
                return String(format: "%.1fk s", Double(seconds) / 1_000)
            } else {
                return String(format: "%.1fM s", Double(seconds) / 1_000_000)
            }
        }
    }
    
    public func i(_ key: String) -> Double {
        trade.patternInformation[key] ?? .nan
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
            printStats(isEnd: false)
            lastPrinted = now
        }
    }
    
    private func printTrade(_ result: TradeResult) {
        let direction = result.isLong ? "Long" : "Short"
                print("❌ \(direction) profit: \(result.profit) time: \(result.tradeDuration) exitReason: \(result.exitReason) entry: \(result.entryPrice), exit: \(result.exitPrice), info: \(result.trade)")
    }
    
    public func printStats(isEnd: Bool) {
        let winners = results.filter { $0.profit > 0 }
        let losers = results.filter { $0.profit < 0 }
        let avgDuration = results.map { $0.exitTime - $0.entryTime }.average()
        let best = results.max(by: { $0.profit < $1.profit })
        let worst = results.min(by: { $0.profit < $1.profit })
        let keys: [String] = results.first != nil ? Array(results.first!.trade.patternInformation.keys) : []
        
        if isEnd  {
            if !winners.isEmpty {
                print("\n✅ Winning Trades:")
                for t in winners {
                    let details = keys.map { "\($0): \(t.i($0))" }.joined(separator: ", ")
                    print("  • \(t.isLong ? "⬆️" : "⬇️") \(t.tradeDuration) \(t.profit) \(t.exitReason), \(details)")
                }
            }
            
            if !losers.isEmpty {
                print("\n❌ Losing Trades:")
                for t in losers {
                    let details = keys.map { "\($0): \(t.i($0))" }.joined(separator: ", ")
                    print("  • \(t.isLong ? "⬆️" : "⬇️") \(t.tradeDuration) \(t.profit) \(t.exitReason), \(details)")
                }
            }
        }
        
        print("""
        ------------------------------------------------
        📊 Trade Statistics:
         • Trades: \(count)
         • Total PnL: \(totalPnL)
         • Win rate: \(String(format: "%.2f", winRate * 100))%
         • Avg Win: \(averageWin)
         • Avg Loss: \(averageLoss)
         • Longs: \(longCount) (Wins: \(longWins)) \(String(format: "%.2f", Double(longWins) / Double(max(longCount, 1)) * 100))%
         • Shorts: \(shortCount) (Wins: \(shortWins)) \(String(format: "%.2f", Double(shortWins) / Double(max(shortCount, 1)) * 100))%
         • Avg Duration: \(Int(avgDuration))s
         • Best Trade: \(best?.profit ?? 0)
         • Worst Trade: \(worst?.profit ?? 0)
        """)
    }
}
