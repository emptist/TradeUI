import Foundation

public protocol MarketSearch: Sendable {
    init()
    /// Connect Service
    func connect() async throws
    func disocnnect() async throws
    /// Asset symbol search stream
    func search(nameOrSymbol symbol: Symbol) async throws -> [any Contract]
}
