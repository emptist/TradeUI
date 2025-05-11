import SwiftUI
import TradingStrategy
import Runtime

struct StrategyPicker: View {
    @EnvironmentObject var strategyRegistry: StrategyRegistry
    @Binding var selectedStrategyId: String
    var action: ((_ strat: Strategy.Type) -> Void)? = nil
    
    private var ids: [String] { strategyRegistry.availableStrategies().map({ $0.id }) }
    
    var body: some View {
        Picker("Strategy", selection: $selectedStrategyId) {
            ForEach(ids, id: \.self) { id in
                Text(strategyRegistry.strategyName(forId: id) ?? id).tag(id)
            }
        }
        .pickerStyle(.automatic)
        .onChange(of: selectedStrategyId, initial: true) {
            guard let strategyType = StrategyRegistry.shared.strategyType(forId: selectedStrategyId) else {
                return
            }
            action?(strategyType.self)
        }
        .padding()
    }
}
