import SwiftUI
import Runtime
import Brokerage

struct SettingsView: View {
    // Store raw string values in UserDefaults to match what InteractiveBrokers expects
    @AppStorage("trading.mode") private var tradingModeRaw: String = TradingMode.paper.rawValue
    @AppStorage("connection.type") private var connectionTypeRaw: String = ConnectionType.gateway.rawValue
    @Environment(\.openURL) private var openURL
    @Environment(TradeManager.self) private var trades

    // Computed bindings for Pickers using the raw storage
    private var tradingMode: Binding<TradingMode> {
        Binding<TradingMode>(
            get: { TradingMode(rawValue: tradingModeRaw) ?? .paper },
            set: { newMode in
                tradingModeRaw = newMode.rawValue
                updateTradingConfiguration()
            }
        )
    }

    private var connectionType: Binding<ConnectionType> {
        Binding<ConnectionType>(
            get: { ConnectionType(rawValue: connectionTypeRaw) ?? .gateway },
            set: { newType in
                connectionTypeRaw = newType.rawValue
                updateTradingConfiguration()
            }
        )
    }
    
    enum TradingMode: String, CaseIterable {
        // Use lowercase raw values so they match the UserDefaults strings read by InteractiveBrokers
        case live = "live"
        case paper = "paper"

        var displayName: String {
            switch self {
            case .live: return "Live"
            case .paper: return "Paper"
            }
        }
    }
    
    enum ConnectionType: String, CaseIterable {
        // Lowercase raw values to match existing UserDefaults checks
        case gateway = "gateway"
        case workstation = "workstation"

        var displayName: String {
            switch self {
            case .gateway: return "Gateway"
            case .workstation: return "Workstation"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Text("Trading Environment")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trading Mode")
                        .font(.caption)
                    Picker("Trading Mode", selection: tradingMode) {
                        ForEach(TradingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Connection Type")
                        .font(.caption)
                    Picker("Connection Type", selection: connectionType) {
                        ForEach(ConnectionType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }

            GroupBox(label: Text("Connection Status")) {
                HStack {
                    Text("Provider:")
                    Text(String(describing: type(of: trades.market)))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
        // Pickers update via computed bindings which call updateTradingConfiguration()
    }
    
    private func updateTradingConfiguration() {
        // Trigger reconnection with new settings
        Task {
            trades.initializeSockets()
        }
    }
}

#Preview {
    SettingsView()
}