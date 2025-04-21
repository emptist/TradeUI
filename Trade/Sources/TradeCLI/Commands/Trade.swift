import ArgumentParser
import Runtime
import Foundation
import TradingStrategy
import Brokerage

struct Trade: @preconcurrency ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trade",
        abstract: "Execute a trade with a symbol and amount"
    )
    
    @Flag(name: .shortAndLong, help: "Enable verbose output for trade details.")
    var verbose = false
    
    @Argument(help: "Strategy .dylib file path.")
    var strategyFile: String
    
    @Argument(help: "The instrument type (e.g., FUT).")
    var type: String = "FUT"
    
    @Argument(help: "The trading symbol (e.g., ESM5).")
    var symbol: String = "ESM5"
    
    @Argument(help: "The trading symbol interval (in seconds).")
    var interval: Double = 60
    
    @Argument(help: "The exchange ID (e.g., CME).")
    var exchange: String = "CME"
    
    @Argument(help: "The currency (e.g., USD).")
    var currency: String = "USD"
    
    @MainActor
    func run() throws {
        let trades = TradeManager(tradeAlertHandler: AlertHandler())
        let registry = StrategyRegistry.shared
        let instrument = Instrument(
            type: type,
            symbol: symbol,
            exchangeId: exchange,
            currency: currency
        )
        
        #if os(macOS)
        guard strategyFile.hasSuffix(".dylib") else {
            if verbose { print("❌ File is not a .dylib") }
            return
        }
        #elseif os(Linux)
        guard strategyFile.hasSuffix(".so") else {
            if verbose { print("❌ File is not a .dylib") }
            return
        }
        #endif
        
        trades.loadStrategy(into: registry, location: strategyFile)
        trades.initializeSockets()
        guard let strategyName = registry.availableStrategies().first else {
            if verbose { print("❌ Something went wrong loading strategies") }
            return
        }
        
        marketData(
            trades: trades,
            contract: instrument,
            interval: interval,
            strategyName: strategyName
        )
        
        // Keep the process alive
        if verbose { print("🏃‍♂️ Running trading process. Press Ctrl+C to stop.") }
        RunLoop.main.run()
    }
    
    @MainActor
    private func marketData(trades: TradeManager, contract: any Contract, interval: TimeInterval, strategyName: String) {
        do {
            guard let strategyType: Strategy.Type = StrategyRegistry.shared.strategy(forName: strategyName) else {
                if verbose { print("❌ Failed to load strategy \(strategyName)") }
                return
            }
            let asset = Asset(
                instrument: Instrument(
                    type: contract.type,
                    symbol: contract.symbol,
                    exchangeId: contract.exchangeId,
                    currency: contract.currency
                ),
                interval: interval,
                strategyName: strategyName
            )
            try trades.marketData(
                contract: contract,
                interval: interval,
                strategyName: strategyName,
                strategyType: strategyType
            )
        } catch {
            if verbose { print("🔴 Failed to subscribe IB market data with error:", error) }
        }
    }
}
