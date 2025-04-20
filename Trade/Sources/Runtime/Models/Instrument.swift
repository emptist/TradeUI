import Foundation
import Brokerage

public struct Asset: Codable, Hashable {
    public var instrument: Instrument
    public var interval: TimeInterval
    public var strategyName: String
    
    public var id: String {
        "\(strategyName)\(instrument.label):\(interval)"
    }
    
    public init(instrument: Instrument, interval: TimeInterval, strategyName: String) {
        self.instrument = instrument
        self.interval = interval
        self.strategyName = strategyName
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
    // MARK: Equity
    public static var CBA: Instrument {
        Instrument(
            type: "STK",
            symbol: "CBA",
            exchangeId: "ASX",
            currency: "AUD"
        )
    }
    
    public static var APPL: Instrument {
        Instrument(
            type: "STK",
            symbol: "AAPL",
            exchangeId: "SMART",
            currency: "USD"
        )
    }
    
    // MARK: Cryptocurrency
    
    public static var BTC: Instrument {
        Instrument(
            type: "CRYPTO",
            symbol: "BTC",
            exchangeId: "PAXOS",
            currency: "USD"
        )
    }
    
    public static var ETH: Instrument {
        Instrument(
            type: "CRYPTO",
            symbol: "ETH",
            exchangeId: "PAXOS",
            currency: "USD"
        )
    }
    
    // MARK: Futures
    
    /// NQ
    public static var NQ: Instrument {
        Instrument(
            type: "FUT",
            symbol: "NQM5",
            exchangeId: "CME",
            currency: "USD"
        )
    }

    
    /// Micro E-Mini S&P 500
    public static var MES: Instrument {
        Instrument(
            type: "FUT",
            symbol: "MESM5",
            exchangeId: "CME",
            currency: "USD"
        )
    }
    
    /// E-Mini S&P 500
    public static var ES: Instrument {
        Instrument(
            type: "FUT",
            symbol: "ESM5",
            exchangeId: "CME",
            currency: "USD"
        )
    }
    
    /// Micro E-mini Russell 2000
    public static var M2K: Instrument {
        Instrument(
            type: "FUT",
            symbol: "M2KM5",
            exchangeId: "CME",
            currency: "USD"
        )
    }
    
    /// E-Mini Russell 2000
    public static var RTY: Instrument {
        Instrument(
            type: "FUT",
            symbol: "RTYM5",
            exchangeId: "CME",
            currency: "USD"
        )
    }
}
