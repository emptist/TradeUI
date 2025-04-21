import Foundation

public protocol MarketSearch: Sendable {
    init()
    /// Connect Service
    func connect() throws
    /// Asset symbol search stream
    func search(nameOrSymbol symbol: Symbol) async throws -> [any Contract]
}
