import Foundation

public protocol MarketOrder: Sendable {
    init()
    /// Connect Service
    func connect() async throws
    func disconnect() async throws
    var account: Account? { get }
    
    /// Retrieve All Active Orders
    func cancelAllOrders() async throws
    func cancelOrder(orderId: Int) async throws
    
    /// Create Orders
    func makeLimitOrder(
        contract product: any Contract,
        action: OrderAction,
        price: Double,
        quantity: Double
    ) async throws
    
    func makeLimitWithTrailingStopOrder(
        contract product: any Contract,
        action: OrderAction,
        price: Double,
        trailStopPrice: Double,
        quantity: Double
    ) async throws
    
    func makeLimitWithStopOrder(
        contract product: any Contract,
        action: OrderAction,
        price: Double,
        stopPrice: Double,
        quantity: Double
    ) async throws
}


