import Foundation
import Brokerage

public struct Asset: Codable, Hashable {
    public var instrument: Instrument
    public var interval: TimeInterval
    public var strategyId: String
    
    public var id: String {
        "\(strategyId)\(instrument.label):\(interval)"
    }
    
    public init(instrument: Instrument, interval: TimeInterval, strategyId: String) {
        self.instrument = instrument
        self.interval = interval
        self.strategyId = strategyId
    }
}

public struct Instrument: Codable, Contract {
    public var type: String
    public var symbol: String
    public var exchangeId: String
    public var currency: String
    
    public init(type: String, symbol: String, exchangeId: String, currency: String) {
        self.type = type
        self.symbol = symbol
        self.exchangeId = exchangeId
        self.currency = currency
    }
}

extension Instrument {
    // MARK: Helper
    private static func currentFuturesSymbol(base: String) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date().addingTimeInterval(14 * 24 * 60 * 60)
        let year = calendar.component(.year, from: now) % 10
        let month = calendar.component(.month, from: now)

        // Determine current front month (March, June, Sep, Dec)
        let codes = [(3, "H"), (6, "M"), (9, "U"), (12, "Z")]
        let frontMonthCode = codes.first { $0.0 >= month }?.1 ?? "H"
        return "\(base)\(frontMonthCode)\(year)"
    }

    // MARK: Equities
    public static var CBA: Instrument {
        Instrument(type: "STK", symbol: "CBA", exchangeId: "ASX", currency: "AUD")
    }

    public static var AAPL: Instrument {
        Instrument(type: "STK", symbol: "AAPL", exchangeId: "SMART", currency: "USD")
    }

    // MARK: Cryptocurrency
    public static var BTC: Instrument {
        Instrument(type: "CRYPTO", symbol: "BTC", exchangeId: "PAXOS", currency: "USD")
    }

    public static var ETH: Instrument {
        Instrument(type: "CRYPTO", symbol: "ETH", exchangeId: "PAXOS", currency: "USD")
    }

    // MARK: Futures
    public static var NQ: Instrument {
        Instrument(type: "FUT", symbol: currentFuturesSymbol(base: "NQ"), exchangeId: "CME", currency: "USD")
    }

    public static var MES: Instrument {
        Instrument(type: "FUT", symbol: currentFuturesSymbol(base: "MES"), exchangeId: "CME", currency: "USD")
    }

    public static var ES: Instrument {
        Instrument(type: "FUT", symbol: currentFuturesSymbol(base: "ES"), exchangeId: "CME", currency: "USD")
    }

    public static var M2K: Instrument {
        Instrument(type: "FUT", symbol: currentFuturesSymbol(base: "M2K"), exchangeId: "CME", currency: "USD")
    }
    
    public static var YM: Instrument {
        Instrument(type: "FUT", symbol: currentFuturesSymbol(base: "YM"), exchangeId: "SMART", currency: "USD")
    }

    public static var RTY: Instrument {
        Instrument(type: "FUT", symbol: currentFuturesSymbol(base: "RTY"), exchangeId: "CME", currency: "USD")
    }

    public static var FDAX: Instrument {
        Instrument(type: "FUT", symbol: "FDAX", exchangeId: "EUREX", currency: "EUR")
    }

    public static var FDXM: Instrument {
        Instrument(type: "FUT", symbol: "FDXM", exchangeId: "EUREX", currency: "EUR")
    }

    public static var FDXS: Instrument {
        Instrument(type: "FUT", symbol: "FDXS", exchangeId: "EUREX", currency: "EUR")
    }
}
