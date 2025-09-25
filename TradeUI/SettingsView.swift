import SwiftUI
import Runtime
import Brokerage

struct SettingsView: View {
    @AppStorage("trading.mode") private var tradingMode: TradingMode = .paper
    @AppStorage("connection.type") private var connectionType: ConnectionType = .gateway
    @Environment(TradeManager.self) private var trades
    
    enum TradingMode: String, CaseIterable {
        case live = "Live"
        case paper = "Paper"
    }
    
    enum ConnectionType: String, CaseIterable {
        case gateway = "Gateway"
        case workstation = "Workstation"
    }
    
    var body: some View {
        Form {
            Section("Trading Environment") {
                Picker("Trading Mode", selection: $tradingMode) {
                    ForEach(TradingMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                Picker("Connection Type", selection: $connectionType) {
                    ForEach(ConnectionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section("Connection Status") {
                HStack {
                    Text("Status:")
                    Text(trades.market.isConnected ? "Connected" : "Disconnected")
                        .foregroundColor(trades.market.isConnected ? .green : .red)
                }
            }
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
        .onChange(of: tradingMode) { oldValue, newValue in
            updateTradingConfiguration()
        }
        .onChange(of: connectionType) { oldValue, newValue in
            updateTradingConfiguration()
        }
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