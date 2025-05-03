import Foundation
import IBKit

extension InteractiveBrokers {
    @discardableResult
    func limitOrder(
        contract: IBContract,
        action: IBAction,
        price: Double,
        quantity: Double
    ) throws -> AsyncStream<any OrderEvent> {
        guard let account = account?.name else {
            throw TradeError.requestError("Missing account identifier")
        }
        var order = IBOrder.limit(price, action: action, quantity: quantity, contract: contract, account: account)
        order.orderID = nextOrderID
        return try streamOrder(order)
    }
    
    func trailingStopOrder(
        contract: IBContract,
        action: IBAction,
        parentOrderId: Int = 0,
        price: Double,
        trailStopPrice: Double,
        quantity: Double
    ) throws -> AsyncStream<any OrderEvent> {
        guard let account = account?.name else {
            throw TradeError.requestError("Missing account identifier")
        }
        var order = IBOrder.trailingStop(stop: trailStopPrice, limit: price, action: action, quantity: quantity, contract: contract, account: account)
        order.orderID = nextOrderID
        order.parentId = parentOrderId
        return try streamOrder(order)
    }
    
    @discardableResult
    func limitWithStopOrder(
        contract: IBContract,
        action: IBAction,
        price: Double,
        stopPrice: Double,
        quantity: Double
    ) throws -> AsyncStream<any OrderEvent> {
        guard let account = account?.name else {
            throw TradeError.requestError("Missing account identifier")
        }
        
        let group = UUID().uuidString
        
        var limitOrder = IBOrder.limit(
            price,
            action: action,
            quantity: quantity,
            contract: contract,
            account: account
        )
        limitOrder.orderID = nextOrderID
        limitOrder.transmit = false
        limitOrder.tif = .goodTilDate
        limitOrder.goodTillDate = Date().addingTimeInterval(8)
        
        var stopOrder = IBOrder.stop(
            stopPrice,
            action: action == .buy ? .sell : .buy,
            quantity: quantity,
            contract: contract,
            account: account,
            validUntil: .day,
            hidden: true,
            extendedTrading: false)
        
        stopOrder.orderID = nextOrderID
        stopOrder.parentId = limitOrder.orderID
        stopOrder.ocaGroup = group
        stopOrder.transmit = true
        
        return AsyncStream { continuation in
            let task1 = Task { [limitOrder] in
                let stream = try streamOrder(limitOrder)
                for try await event in stream {
                    continuation.yield(event)
                }
            }

            let task2 = Task { [stopOrder] in
                let stream = try streamOrder(stopOrder)
                for try await event in stream {
                    continuation.yield(event)
                }
            }

            continuation.onTermination = { _ in
                task1.cancel()
                task2.cancel()
            }

            Task {
                _ = await task1.result
                _ = await task2.result
                continuation.finish()
            }
        }
    }
    
    @discardableResult
    func limitWithTrailingStopOrder(
        contract: IBContract,
        action: IBAction,
        price: Double,
        trailStopPrice: Double,
        quantity: Double
    ) throws -> AsyncStream<any OrderEvent> {
        guard let account = account?.name else {
            throw TradeError.requestError("Missing account identifier")
        }
        
        let group = UUID().uuidString
        
        var limitOrder = IBOrder.limit(price, action: action, quantity: quantity, contract: contract, account: account)
        limitOrder.orderID = nextOrderID
        limitOrder.transmit = false
        
        var stopOrder = IBOrder.trailingStop(
            stop: trailStopPrice,
            limit: price,
            action: action == .buy ? .sell : .buy,
            quantity: quantity,
            contract: contract,
            account: account
        )
        stopOrder.orderID = nextOrderID
        stopOrder.parentId = limitOrder.orderID
        stopOrder.ocaGroup = group
        stopOrder.transmit = true
        
        return AsyncStream { continuation in
            let task1 = Task { [limitOrder] in
                let stream = try streamOrder(limitOrder)
                for try await event in stream {
                    continuation.yield(event)
                }
            }

            let task2 = Task { [stopOrder] in
                let stream = try streamOrder(stopOrder)
                for try await event in stream {
                    continuation.yield(event)
                }
            }

            continuation.onTermination = { _ in
                task1.cancel()
                task2.cancel()
            }

            Task {
                _ = await task1.result
                _ = await task2.result
                continuation.finish()
            }
        }
    }
    
    private func streamOrder(_ order: IBOrder) throws -> AsyncStream<any OrderEvent> {
        let requestID = client.nextRequestID
        try client.placeOrder(requestID, order: order)
        
        return AsyncStream { continuation in
            Task {
                for await event in await client.eventFeed {
                    guard let indexed = event as? IBIndexedEvent, indexed.requestID == requestID else { continue }
                    
                    switch indexed {
                    case let event as OrderEvent:
                        continuation.yield(event)
                    case let event as IBServerError:
                        print("❌ Order error: \(event.message)")
                        continuation.finish()
                        return
                    default: continue
                    }
                }
                continuation.finish()
            }
        }
    }
}

public protocol OrderEvent: Sendable {}
extension IBOrder: OrderEvent {}
extension IBOpenOrder: OrderEvent {}
extension IBOpenOrderEnd: OrderEvent {}
extension IBOrderStatus: OrderEvent {}
extension IBOrderExecution: OrderEvent {}
extension IBOrderExecutionEnd: OrderEvent {}
extension IBOrderCompletion: OrderEvent {}
extension IBOrderCompetionEnd: OrderEvent {}

extension IBOrder: Order {
    public var symbol: String {  contract.localSymbol ?? contract.symbol }
    public var orderAction: OrderAction { self.action == .buy ? .buy : .sell }
    public var limitPrice: Double? { lmtPrice }
    public var stopPrice: Double? { auxPrice }
    public var totalCount: Double { totalQuantity }
    public var orderStatus: String { orderState.status.rawValue }
    public var timestamp: Date? { orderState.completedTime }
    public var filledCount: Double {
        set {
            filledQuantity = newValue
        }
        get {
            filledQuantity ?? 0
        }
    }
}
