import Foundation
import TradingStrategy

/// A registry for dynamically registering and retrieving trading strategies.
@MainActor
public final class StrategyRegistry: ObservableObject {
    public static let shared = StrategyRegistry()
    public var defaultStrategyType: Strategy.Type = TradingStrategy.DoNothingStrategy.self
    
    /// Holds registered strategy types by name.
    private var strategies: [String: Strategy.Type] = [:]

    public func strategyType(forId id: String) -> Strategy.Type? {
        strategies[id]
    }
    
    public func strategyName(forId id: String) -> String? {
        strategies[id]?.name
    }

    /// Returns the list of registered strategy names.
    public func availableStrategies() -> [Strategy.Type] {
        return Array(strategies.values)
    }
    
    /// Registers a strategy by providing its type and a unique name.
    public func register<T: Strategy>(strategyType type: T.Type) {
        strategies[type.id] = type
    }
    
    public func reset() {
        strategies = [:]
    }
}
