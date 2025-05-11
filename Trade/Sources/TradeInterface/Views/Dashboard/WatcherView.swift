import SwiftUI
import Runtime
import Brokerage
import TradingStrategy

public struct WatcherView: View {
    @Environment(TradeManager.self) private var trades
    @State private var isMarketOpen: (isOpen: Bool, timeUntilChange: TimeInterval?) = (false, nil)
    @State private var strategy: Strategy?
    @State private var interval: TimeInterval?

    let watcher: Watcher?
    let showActions: Bool
    let showChart: Bool

    // Timer to fetch updates every second
    private let updateTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    public init(watcher: Watcher?, showChart: Bool = true, showActions: Bool = false) {
        self.watcher = watcher
        self.showChart = showChart
        self.showActions = showActions
    }

    public var body: some View {
        if let watcher {
            VStack {
                GeometryReader { geometry in
                    HStack {
                        StrategyQuoteView(
                            watcher: watcher,
                            showActions: showActions
                        )
                        .frame(width: geometry.size.width * 4.0/7.0, height: geometry.size.height)
                        Group {
                            if let strategy {
                                confidenceView(strategy: strategy)
                                StrategyCheckList(strategy: strategy)
                            } else {
                                Spacer()
                            }
                        }
                        .frame(width: geometry.size.width * 3.0/7.0, height: geometry.size.height)
                    }
                }
                .frame(height: 32)
                if showChart, let strategy, let interval {
                    StrategyChart(
                        strategy: strategy,
                        interval: interval
                    )
                    .id(watcher.id)
                }
            }
            .id(watcher.id + "_view")
            .onReceive(updateTimer) { _ in
                Task { await fetchWatcherState() }
            }
        }
    }

    @ViewBuilder
    private func confidenceView(strategy: any Strategy) -> some View {
        VStack(alignment: .center, spacing: 4) {
            if strategy.patternIdentified != nil {
                Text("Confidence")
                    .lineLimit(1)
                    .foregroundColor(.white.opacity(0.4))
                    .font(.caption)
            }
            switch strategy.patternIdentified {
            case let .buy(confidence):
                Text("\(confidence * 100)%%")
                    .lineLimit(1)
                    .foregroundColor(.green)
                    .font(.subheadline)
            case let .sell(confidence):
                Text("\(confidence * 100)%%")
                    .lineLimit(1)
                    .foregroundColor(.red)
                    .font(.subheadline)
            default:
                EmptyView()
            }
        }
    }
    
    // MARK: - Async Fetching
    
    private func fetchWatcherState() async {
        guard let watcher else { return }
        strategy = await watcher.watcherState.getStrategy()
        interval = watcher.interval
        isMarketOpen = await watcher.watcherState.getTradingHours()?.isMarketOpen() ?? (false, nil)
    }
}
