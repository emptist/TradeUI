import SwiftUI
import Runtime
import Brokerage
import TradingStrategy

struct DateRange: Hashable {
    var start: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    var end: Date = Date()
}

public struct WatcherView: View {
    @Environment(TradeManager.self) private var trades
    @State private var isMarketOpen: (isOpen: Bool, timeUntilChange: TimeInterval?) = (false, nil)
    @State private var strategy: Strategy?
    @State private var interval: TimeInterval?
    
    @State private var selectedDataMode: Watcher.DataMode = .live
    @State private var previewDates: DateRange

    let watcher: Watcher?
    let showActions: Bool
    let showChart: Bool

    // Timer to fetch updates every second
    private let updateTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    public init(watcher: Watcher?, showChart: Bool = true, showActions: Bool = false) {
        self.watcher = watcher
        self.showChart = showChart
        self.showActions = showActions
        
        let now = Date()
        let start = Calendar.current.date(byAdding: .second, value: -Int(watcher?.interval ?? 60) * 80, to: now) ?? now
        self._previewDates = State(initialValue: DateRange(
            start: start,
            end: now
        ))
    }

    public var body: some View {
        if let watcher {
            VStack {
                if showChart, !watcher.isSimulation {
                    dataModeView
                }
                StrategyQuoteView(
                    watcher: watcher,
                    showActions: showActions
                )
                if let strategy {
                    StrategyCheckList(strategy: strategy)
                    
                    if showChart, let interval {
                        StrategyChart(
                            strategy: strategy,
                            interval: interval,
                            trades: Array(watcher.tradeAggregator.activeSimulationTrades.values)
                        )
                        .id(watcher.id)
                        .overlay(alignment: .bottomLeading) {
                            HStack {
                                Button("Pull") {
                                    watcher.pullNext = .greatestFiniteMagnitude
                                }
                                
                                Button("Pull 1") {
                                    watcher.pullNext = 1
                                }
                                
                                Button("Order") {
                                    Task {
                                        await watcher.tradeAggregator.placeManualTrade(from: watcher, isLong: true)
                                    }
                                }
                            }.padding()
                        }
                    }
                }
            }
            .id(watcher.id + "_view")
            .onReceive(updateTimer) { _ in
                Task { await fetchWatcherState() }
            }
            .onChange(of: selectedDataMode) {
                Task {
                    switch selectedDataMode {
                    case .live:
                        watcher.reconnectToLiveFeed(using: trades.market, fileProvider: trades.fileProvider)
                    case .historical(let start, let end):
                        await watcher.switchToHistorical(start: start, end: end, using: trades.market)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var dataModeView: some View {
        HStack(spacing: 8) {
            Picker("Mode", selection: $selectedDataMode) {
                Text("Live").tag(Watcher.DataMode.live)
                Text("Custom").tag(Watcher.DataMode.historical(start: previewDates.start, end: previewDates.end))
            }
            .pickerStyle(.segmented)
            
            if case .historical = selectedDataMode {
                DatePicker("Start", selection: $previewDates.start, displayedComponents: [.date, .hourAndMinute])
                DatePicker("End", selection: $previewDates.end, displayedComponents: [.date, .hourAndMinute])
                HStack {
                    Button("⏪ 10x") {
                        shiftTimeWindow(-10)
                    }
                    
                    Button("⏪") {
                        shiftTimeWindow(-1)
                    }
                    Button("⏩") {
                        shiftTimeWindow(1)
                    }
                    
                    Button("10x ⏩") {
                        shiftTimeWindow(10)
                    }
                    
                    Button("⏭️") {
                        previewDates = DateRange()
                    }
                }
            }
        }
        .padding([.horizontal, .top])
        .onChange(of: previewDates) {
            selectedDataMode = .historical(start: previewDates.start, end: previewDates.end)
            
            Task {
                guard let watcher else { return }
                await watcher.switchToHistorical(start: previewDates.start, end: previewDates.end, using: trades.market)
            }
        }
    }
    
    private func shiftTimeWindow(_ shift: Int) {
        guard let interval, let timeClose = strategy?.candles.last?.timeClose else { return }
        
        let shift = interval * Double(shift)
        let lastEnd = Date(timeIntervalSince1970: timeClose + shift)
        let windowSize = previewDates.end.timeIntervalSince(previewDates.start)
        let newStart = lastEnd.addingTimeInterval(-windowSize)
        
        previewDates = DateRange(start: newStart, end: lastEnd)
    }
    
    // MARK: - Async Fetching
    
    private func fetchWatcherState() async {
        guard let watcher else { return }
        strategy = await watcher.watcherState.getStrategy()
        interval = watcher.interval
        isMarketOpen = await watcher.watcherState.getTradingHours()?.isMarketOpen() ?? (false, nil)
    }
}
