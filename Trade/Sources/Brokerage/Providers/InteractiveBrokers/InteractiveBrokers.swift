import Foundation
import IBKit

public class InteractiveBrokers: @unchecked Sendable, Market {
    private struct Asset: Hashable {
        var contract: any Contract
        var interval: TimeInterval

        public func hash(into hasher: inout Hasher) {
            hasher.combine(contract)
            hasher.combine(interval)
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            return lhs.contract.hashValue == rhs.contract.hashValue
                && lhs.interval == rhs.interval
        }
    }

    // Stored client that can be recreated when settings change.
    private let clientLock = DispatchQueue(label: "InteractiveBrokers.client.sync")
    private var _client: IBClient?
    private var eventTask: Task<Void, Never>?

    var client: IBClient {
        clientLock.sync {
            if let c = _client { return c }
            let c = makeClient()
            _client = c
            startEventLoop(for: c)
            return c
        }
    }

    /// Create a client based on UserDefaults; comparison is case-insensitive so stored values like "Live" or "live" both work.
    private func makeClient() -> IBClient {
        let tradingMode = UserDefaults.standard.string(forKey: "trading.mode")?.lowercased() ?? "paper"
        let connectionType = UserDefaults.standard.string(forKey: "connection.type")?.lowercased() ?? "gateway"

        let type: IBClient.ConnectionType = connectionType == "gateway" ? .gateway : .workstation
        let client = tradingMode == "live"
            ? IBClient.live(id: 0, type: type) : IBClient.paper(id: 0, type: type)

        AppLog.debug("InteractiveBrokers: makeClient -> tradingMode=\(tradingMode), connectionType=\(connectionType), client=\(client)")
        return client
    }

    private func startEventLoop(for client: IBClient) {
        // Cancel any previous event loop attached to an old client
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await anyEvent in await client.eventFeed {
                switch anyEvent {
                case let event as IBManagedAccounts:
                    for accountId in event.identifiers {
                        await self.startListening(accountId: accountId)
                    }
                case let event as IBAccountSummary:
                    self.updateAccountData(event: event)
                case let event as IBAccountUpdate:
                    self.updateAccountData(event: event)
                case let event as IBPosition:
                    await self.updatePositions(event)
                case let event as IBPositionPNL:
                    self.updatePositions(event)
                case let event as IBPortfolioValue:
                    self.updatePortfolio(event)
                case let event as OrderEvent:
                    self.updateAccountOrders(event: event)
                default:
                    break
                }
            }
        }
    }

    /// Force recreation of the underlying IBClient and restart its event loop. Call this after UserDefaults change.
    public func recreateClient() {
        clientLock.sync {
            AppLog.info("InteractiveBrokers: recreateClient() — recreating IBClient from UserDefaults")
            _client = makeClient()
            if let c = _client {
                startEventLoop(for: c)
                AppLog.info("InteractiveBrokers: recreateClient() — started event loop for new client: \(c)")
            }
        }
    }
    private let queue = DispatchQueue(
        label: "InteractiveBrokers.syncQueue", attributes: .concurrent)
    private var _accounts: [String: Account] = [:]

    public var accounts: [String: Account] {
        get {
            queue.sync { _accounts }
        }
        set {
            queue.async(flags: .barrier) { self._accounts = newValue }
        }
    }

    public var account: Account? {
        queue.sync {
            self.getDefaultAccount()
        }
    }

    private var _unsubscribeMarketData: Set<Asset> = []
    private var _unsubscribeQuote: Set<IBContract> = []
    private let unsubscribeQueue = DispatchQueue(
        label: "IB.unsubscribe.sync", attributes: .concurrent)

    private var unsubscribeMarketData: Set<Asset> {
        get { unsubscribeQueue.sync { _unsubscribeMarketData } }
        set { unsubscribeQueue.async(flags: .barrier) { self._unsubscribeMarketData = newValue } }
    }

    private var unsubscribeQuote: Set<IBContract> {
        get { unsubscribeQueue.sync { _unsubscribeQuote } }
        set { unsubscribeQueue.async(flags: .barrier) { self._unsubscribeQuote = newValue } }
    }

    required public init() {
        Task { [weak self] in
            guard let self else { return }
            for await anyEvent in await self.client.eventFeed {
                switch anyEvent {
                case let event as IBManagedAccounts:
                    for accountId in event.identifiers {
                        await self.startListening(accountId: accountId)
                    }
                case let event as IBAccountSummary:
                    self.updateAccountData(event: event)
                case let event as IBAccountUpdate:
                    self.updateAccountData(event: event)
                case let event as IBPosition:
                    await self.updatePositions(event)
                case let event as IBPositionPNL:
                    self.updatePositions(event)
                case let event as IBPortfolioValue:
                    self.updatePortfolio(event)
                case let event as OrderEvent:
                    self.updateAccountOrders(event: event)
                default:
                    break
                }
            }
        }
    }

    public func connect() async throws {
        do {
            AppLog.info("InteractiveBrokers: connect() — delegating to client.connect()")
            try await client.connect()
            AppLog.info("InteractiveBrokers: connect() succeeded")
        } catch {
            AppLog.error("failed to connect to Interactive Brokers: \(error)")
            throw error
        }
    }

    public func disconnect() async throws {
        AppLog.info("InteractiveBrokers: disconnect() — delegating to client.disconnect()")
        await client.disconnect()
        AppLog.info("InteractiveBrokers: disconnect() returned")
    }

    func contract(_ product: any Contract) -> IBContract {
        let contract: IBContract
        if product.type == IBSecuritiesType.future.rawValue {
            contract = IBContract.future(
                localSymbol: product.symbol,
                currency: product.currency,
                exchange: IBExchange(rawValue: product.exchangeId) ?? .CME
            )
        } else {
            contract = IBContract(
                symbol: product.symbol,
                secType: IBSecuritiesType(rawValue: product.type) ?? .stock,
                currency: product.currency,
                exchange: IBExchange(rawValue: product.exchangeId) ?? .SMART
            )
        }
        return contract
    }

    // MARK: - Market Symbol Search

    public func search(nameOrSymbol symbol: Symbol) async throws -> [any Contract] {
        try await Product.fetchProducts(symbol: symbol, productType: [.stock])
    }

    // MARK: Market Data

    public func unsubscribeMarketData(contract: any Contract, interval: TimeInterval) {
        unsubscribeMarketData.insert(Asset(contract: contract, interval: interval))
    }

    public func marketData(
        contract product: any Contract,
        interval: TimeInterval,
        userInfo: [String: Any]
    ) throws -> AsyncStream<CandleData> {
        let contract = self.contract(product)
        let buffer = userInfo[MarketDataKey.bufferInfo.rawValue] as? TimeInterval ?? interval
        let barSize = IBBarSize(timeInterval: interval)
        unsubscribeMarketData.remove(Asset(contract: product, interval: interval))

        return try historicBarPublisher(
            contract: contract,
            barSize: barSize,
            duration: DateInterval(start: Date(timeIntervalSinceNow: -buffer), end: .distantFuture)
        )
    }

    public func marketDataSnapshot(
        contract product: any Contract,
        interval: TimeInterval,
        startDate: Date,
        endDate: Date? = nil,
        userInfo: [String: Any]
    ) throws -> AsyncStream<CandleData> {
        try historicBarPublisher(
            contract: self.contract(product),
            barSize: IBBarSize(timeInterval: interval),
            duration: DateInterval(start: startDate, end: endDate ?? Date())
        )
    }

    public func tradingHour(_ product: any Contract) async throws -> [TradingHour] {
        let details = try await contractDetails(product)

        // minimum price increment
        let tickSize = details.minimumTick
        // $ per tick (customize per contract)
        let tickValue = details.multiplier.flatMap(Double.init) ?? 1.0

        return details.liquidHours?.map {
            TradingHour(
                open: $0.open,
                close: $0.close,
                status: $0.status.rawValue,
                tickValue: tickValue,
                tickSize: tickSize
            )
        } ?? []
    }

    private func contractDetails(_ product: any Contract) async throws -> IBContractDetails {
        let requestID = client.nextRequestID
        let request = IBContractDetailsRequest(
            requestID: requestID, contract: self.contract(product))
        for await event: IBContractDetails in try await client.stream(request: request) {
            return event
        }
        throw TradeError.somethingWentWrong("No contract details received")
    }

    // MARK: Private IB Type handling

    private func unsubscribeMarketData(_ requestID: Int) async throws {
        try await client.cancelHistoricalData(requestID)
    }

    // publishes one time event
    private func historicBarPublisher(
        contract: IBContract,
        barSize size: IBBarSize,
        duration: DateInterval
    ) throws -> AsyncStream<CandleData> {
        let symbol = contract.localSymbol ?? contract.symbol
        let interval: TimeInterval = size.timeInterval
        let requestID = client.nextRequestID
        let request = IBPriceHistoryRequest(
            requestID: requestID,
            contract: contract,
            size: size,
            source: .trades,
            lookback: duration,
            extendedTrading: true,
            includeExpired: false
        )
        return AsyncStream { continuation in
            Task { [weak self, continuation] in
                guard let stream = await self?.client.eventFeed else {
                    continuation.finish()
                    return
                }
                try await self?.client.send(request: request)
                for await event in stream {
                    guard
                        let event = event as? IBIndexedEvent,
                        event.requestID == request.requestID
                    else { continue }

                    let asset = Asset(contract: contract, interval: interval)
                    if let data = self?.unsubscribeMarketData, data.contains(asset) {
                        self?.unsubscribeMarketData.remove(asset)
                        self?.unsubscribeQuote.insert(contract)
                        try? await self?.unsubscribeMarketData(requestID)
                        continuation.finish()
                        return
                    }
                    switch event {
                    case let event as IBPriceHistory:
                        let bars = event.prices
                            .sorted { $0.date < $1.date }
                            .map { Bar(bar: $0, interval: interval) }
                        continuation.yield(
                            CandleData(symbol: symbol, interval: interval, bars: bars))
                    case let event as IBPriceBarUpdate:
                        let bar = Bar(bar: event.bar, interval: interval)
                        continuation.yield(
                            CandleData(symbol: symbol, interval: interval, bars: [bar]))
                    case let error as IBServerError:
                        AppLog.error("IBServerError: \(error.message)")
                    default:
                        continue
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: Market Order

    public func cancelAllOrders() async throws {
        try await client.cancelAllOrders()
    }

    public func cancelOrder(orderId: Int) async throws {
        try await client.cancelOrder(orderId)
    }

    public func makeMarketOrder(
        contract product: any Contract,
        action: OrderAction,
        price: Double,
        quantity: Double,
        group: String?
    ) async throws {
        try await marketOrder(
            contract: self.contract(product),
            action: action == .buy ? .buy : .sell,
            price: price,
            quantity: quantity,
            group: group
        )
    }

    public func makeLimitOrder(
        contract product: any Contract,
        action: OrderAction,
        price: Double,
        quantity: Double,
        group: String?
    ) async throws {
        try await limitOrder(
            contract: self.contract(product),
            action: action == .buy ? .buy : .sell,
            price: price,
            quantity: quantity,
            group: group
        )
    }

    public func makeLimitWithTrailingStopOrder(
        contract product: any Contract,
        action: OrderAction,
        price: Double,
        targets: (takeProfit: Double?, stopLoss: Double?),
        quantity: Double,
        group: String?
    ) async throws {
        try limitWithTrailingStopOrder(
            contract: self.contract(product),
            action: action == .buy ? .buy : .sell,
            price: price,
            targets: targets,
            quantity: quantity,
            group: group ?? UUID().uuidString
        )
    }

    public func makeLimitWithStopOrder(
        contract product: any Contract,
        action: OrderAction,
        price: Double,
        targets: (takeProfit: Double?, stopLoss: Double?),
        quantity: Double,
        group: String?
    ) async throws {
        try limitWithStopOrder(
            contract: self.contract(product),
            action: action == .buy ? .buy : .sell,
            price: price,
            targets: targets,
            quantity: quantity,
            group: group ?? UUID().uuidString
        )
    }

    private func unsubscribeQuote(_ requestID: Int) async {
        try? await client.unsubscribeMarketData(requestID)
    }

    /// publishes live bid, ask, last snapshorts taken every 250ms of requested contract
    /// - Parameters:
    /// - contract: security description
    /// - extendedSession: include data from extended trading hours
    public func quotePublisher(contract product: any Contract) throws -> AsyncStream<Quote> {
        let requestID = client.nextRequestID
        let contract = self.contract(product)
        let request = IBMarketDataRequest(requestID: requestID, contract: contract)
        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                let stream: AsyncStream<IBTick> = try await self.client.stream(request: request)
                for await event in stream {
                    if self.unsubscribeQuote.contains(contract) {
                        await self.unsubscribeQuote(requestID)
                        self.unsubscribeQuote.remove(contract)
                    }
                    if let quote = Quote(tick: event, contract: contract) {
                        continuation.yield(quote)
                    }
                }
                continuation.finish()
            }
        }
    }
}

extension IBContract: @retroactive Hashable {}
extension IBContract: @retroactive Equatable {}
extension IBContract: Contract {
    public var type: String {
        self.securitiesType.rawValue
    }

    public var exchangeId: String {
        self.exchange?.rawValue ?? ""
    }
}

extension Bar {
    init(bar update: IBPriceBar, interval: TimeInterval) {
        self.init(
            timeOpen: update.date.timeIntervalSince1970,
            interval: interval,
            priceOpen: update.open,
            priceHigh: update.high,
            priceLow: update.low,
            priceClose: update.close,
            volume: update.volume
        )
    }
}

extension Quote {
    init?(tick: IBTick, contract: IBContract) {
        let context: Quote.Context
        switch tick.type {
        case .BidPrice: context = .bidPrice
        case .AskPrice: context = .askPrice
        case .LastPrice: context = .lastPrice
        case .Volume: context = .volume
        default: return nil
        }
        self.init(
            contract: contract,
            date: tick.date,
            type: context,
            value: context == .volume ? tick.value * 100 : tick.value
        )
    }
}
