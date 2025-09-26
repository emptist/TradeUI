import SwiftUI
import Runtime
import Brokerage
import TradingStrategy
import SwiftUIComponents

public struct SnapshotView: View {
    @AppStorage("selected.strategy.id") private var selectedStrategyId: String = TradingStrategy.DoNothingStrategy.id
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var strategyRegistry: StrategyRegistry
    @State var strategy: (any Strategy)? = nil
    @State var interval: TimeInterval? = nil
    @State var trades: [Trade] = []
    
    let node: FileSnapshotsView.FileNode?
    let fileProvider: CandleFileProvider
    
    public init(node: FileSnapshotsView.FileNode?, fileProvider: CandleFileProvider) {
        self.node = node
        self.fileProvider = fileProvider
    }
    
    private var selectedStrategyBinding: Binding<String> {
        Binding(
            get: { selectedStrategyId },
            set: { value, transaction in
                selectedStrategyId = value
        })
    }
    
    public var body: some View {
        Group {
            VStack {
                StrategyPicker(selectedStrategyId: selectedStrategyBinding, action: loadData(_:))
                if let strategy {
                    VStack {
                        StrategyCheckList(strategy: strategy)
                        StrategyChart(strategy: strategy, interval: interval ?? 60, trades: [])
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .onAppear {
                            guard selectedStrategyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            selectedStrategyId = strategyRegistry.defaultStrategyType.id
                        }
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 450)
        .padding(20)
        .overlay(alignment: .topTrailing) {
            #if !os(macOS)
            Button("Dismiss") {
                if Bundle.main.isMacOS {
                    dismiss()
                } else {
                    presentationMode.wrappedValue.dismiss()
                }
            }.padding()
            #endif
        }
    }
    
    private func loadData(_ strat: Strategy.Type) {
        guard let node else { return }
        do {
            let candleData = try fileProvider.loadFile(url: node.url)
            strategy = strat.init(candles: candleData?.bars ?? [])
            interval = candleData?.interval
        } catch {
            print("Failed to load data for:", node.url)
        }
    }
}
