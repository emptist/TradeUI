import Foundation
import IBKit

extension InteractiveBrokers {
    @discardableResult
    func limitOrder(
        contract: IBContract,
        action: IBAction,
        price: Double,
        quantity: Double
    ) async throws -> AsyncStream<any OrderEvent> {
        guard let account = account?.name else {
            throw TradeError.requestError("Missing account identifier")
        }
        var order = IBOrder.limit(price, action: action, quantity: quantity, contract: contract, account: account)
        order.orderID = nextOrderID
        return try await streamOrder(order)
    }
    
    func trailingStopOrder(
        contract: IBContract,
        action: IBAction,
        parentOrderId: Int = 0,
        price: Double,
        trailStopPrice: Double,
        quantity: Double
    ) async throws -> AsyncStream<any OrderEvent> {
        guard let account = account?.name else {
            throw TradeError.requestError("Missing account identifier")
        }
        var order = IBOrder.trailingStop(stop: trailStopPrice, limit: price, action: action, quantity: quantity, contract: contract, account: account)
        order.orderID = nextOrderID
        order.parentId = parentOrderId
        return try await streamOrder(order)
    }
    
    @discardableResult
    func limitWithStopOrder(
        contract: IBContract,
        action: IBAction,
        price: Double,
        targets: (takeProfit: Double?, stopLoss: Double?),
        quantity: Double
    ) throws -> AsyncStream<any OrderEvent> {
        guard let account = account?.name else {
            throw TradeError.requestError("Missing account identifier")
        }
        
        let group = UUID().uuidString
        let opposite = action == .buy ? IBAction.sell : .buy
        var orders: [IBOrder] = []
        
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
        orders.append(limitOrder)
        
        if let stopLoss = targets.stopLoss {
            var stopOrder = IBOrder.stop(
                stopLoss,
                action: opposite,
                quantity: quantity,
                contract: contract,
                account: account,
                validUntil: .day,
                hidden: true,
                extendedTrading: true
            )
            
            stopOrder.orderID = nextOrderID
            stopOrder.parentId = limitOrder.orderID
            stopOrder.ocaGroup = group
            stopOrder.ocaType = .cancelBlock
            stopOrder.transmit = false
            orders.append(stopOrder)
        }
        
        if let takeProfit = targets.takeProfit {
            var tpOrder = IBOrder.limit(
                takeProfit,
                action: opposite,
                quantity: quantity,
                contract: contract,
                account: account
            )
            tpOrder.orderID = nextOrderID
            tpOrder.parentId = limitOrder.orderID
            tpOrder.ocaGroup = group
            tpOrder.ocaType = .cancelBlock
            tpOrder.transmit = false
            orders.append(tpOrder)
        }
        
        if let lastIndex = orders.indices.last {
            orders[lastIndex].transmit = true
        }
        return streamOrders(orders)
    }
    
    @discardableResult
    func limitWithTrailingStopOrder(
        contract: IBContract,
        action: IBAction,
        price: Double,
        targets: (takeProfit: Double?, stopLoss: Double?),
        quantity: Double
    ) throws -> AsyncStream<any OrderEvent> {
        guard let account = account?.name else {
            throw TradeError.requestError("Missing account identifier")
        }
        
        let group = UUID().uuidString
        var orders: [IBOrder] = []
        
        var limitOrder = IBOrder.limit(price, action: action, quantity: quantity, contract: contract, account: account)
        limitOrder.orderID = nextOrderID
        limitOrder.transmit = false
        orders.append(limitOrder)
        
        if let stopLoss = targets.stopLoss {
            var stopOrder = IBOrder.trailingStop(
                stop: stopLoss,
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
            orders.append(stopOrder)
        }
        
        return streamOrders(orders)
    }
    
    private func streamOrder(_ order: IBOrder) async throws -> AsyncStream<any OrderEvent> {
        let requestID = client.nextRequestID
        try await client.placeOrder(requestID, order: order)
        
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
    
    private func streamOrders(_ orders: [IBOrder]) -> AsyncStream<any OrderEvent> {
        AsyncStream { continuation in
            var tasks: [Task<Void, Error>] = []

            for order in orders {
                tasks.append(Task { [order] in
                    let stream = try await streamOrder(order)
                    for try await event in stream {
                        continuation.yield(event)
                    }
                })
            }

            continuation.onTermination = { [tasks] _ in
                tasks.forEach { $0.cancel() }
            }

            Task {
                for task in tasks {
                    _ = await task.result
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
