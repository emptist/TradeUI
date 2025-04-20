import ArgumentParser

@main
struct TradeWithIt: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "TradeWithIt",
        abstract: "A command-line interface for executing trading strategies.",
        subcommands: [Help.self, Trade.self],
        defaultSubcommand: Help.self
    )
    
    // Help subcommand (implicitly available, but we define it as default)
    struct Help: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "help",
            abstract: "Display help information"
        )
        
        var fileExtension: String {
#if os(Linux)
            return ".so"
#else
            return ".dylib"
#endif
        }
        
        func run() throws {
            print(
            """
            TradeWithIt: A command-line interface for TradeApp
            TradeWithIt enables algorithmic trading by integrating market analysis tools and trading strategies. It leverages:
            - TradeUI: Provides market data and analysis tools for stocks and options, powered by APIs and AI-driven insights.
              Learn more: https://github.com/TradeWithIt/TradeUI
            - Strategy: Implements trading strategies for automated trade execution.
              Learn more: https://github.com/TradeWithIt/Strategy

            Usage:
              TradeWithIt <subcommand> [options]

            Subcommands:
              help    Display this help information
              trade   Execute a trading strategy with an instrument (type, symbol, exchange, currency)

            For detailed help on a subcommand, run:
              TradeWithIt <subcommand> --help
              
            Trade Subcommand Arguments:
              <strategyFile>    Path to the \(fileExtension) file containing the trading strategy
              <type>            Instrument type (default: FUT)
              <symbol>          Trading symbol (default: ESM5)
              <interval>        Market data interval in seconds (default: 60)
              <exchange>        Exchange ID (default: CME)
              <currency>        Currency (default: USD)
              --verbose, -v     Enable verbose output for trade details

            Examples:
              TradeWithIt trade /path/to/strategy\(fileExtension) FUT ESM5 60 CME USD
              TradeWithIt trade /path/to/strategy\(fileExtension) --verbose
              TradeWithIt help
              TradeWithIt trade --help
            
            For detailed help on a subcommand, run:
              TradeWithIt <subcommand> --help
            """
            )
        }
    }
}
