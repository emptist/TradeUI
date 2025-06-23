import SwiftUI
import TradingStrategy


public struct StrategyCheckList: View {
    let strategy: any Strategy
    
    public init(strategy: any Strategy) {
        self.strategy = strategy
    }
    
    public var body: some View {
        HStack {
            confidenceView(strategy: strategy)
            Divider().frame(height: 16)
            ForEach(Array(strategy.patternInformation.keys.sorted()), id: \.self) { key in
                checkItem(name: key) { strategy.patternInformation[key] ?? 0.0 }
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func confidenceView(strategy: any Strategy) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text("Confidence")
                .lineLimit(1)
                .foregroundColor(.white.opacity(0.4))
                .font(.caption)
            switch strategy.patternIdentified {
            case let .buy(confidence):
                Text("⬆️ \(Int(confidence * 100))%")
                    .lineLimit(1)
                    .foregroundColor(.blue)
                    .font(.subheadline)
            case let .sell(confidence):
                Text("⬇️ \(Int(confidence * 100))%")
                    .lineLimit(1)
                    .foregroundColor(.blue)
                    .font(.subheadline)
            default:
                Text("-")
                    .lineLimit(1)
                    .foregroundColor(.gray)
                    .font(.subheadline)
            }
        }
    }
    
    private func checkItem(name: String, _ condition: () -> Double) -> some View {
        let confidence = condition()
        let isFullfiled: Bool = confidence >= 0.7
        return VStack(alignment: .center, spacing: 4) {
            Text(name)
                .lineLimit(1)
                .foregroundColor(.white.opacity(0.4))
                .font(.caption)
            Text(String(format: "%.1f", confidence))
                .lineLimit(1)
                .foregroundColor(isFullfiled ? .green : .red)
                .font(.subheadline)
        }
    }
}
