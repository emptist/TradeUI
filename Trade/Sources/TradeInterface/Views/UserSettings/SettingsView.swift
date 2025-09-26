//
//  SettingsView.swift
//  TradeApp
//
//  Created by jk on 26/09/2025.
//


import Brokerage
import Runtime
import SwiftUI

// Move enums outside of the struct to ensure they're available during property initialization

// Settings sections for sidebar navigation
enum SettingsSection: Hashable, CaseIterable, Identifiable {
    case general
    case debug
    case status
    
    // Required for Identifiable conformance
    var id: Self { self }
    
    var title: String {
        switch self {
        case .general: return "General"
        case .debug: return "Debug"
        case .status: return "Status"
        }
    }
    
    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .debug: return "info.circle"
        case .status: return "network"
        }
    }
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

public struct SettingsView: View {
    // Store raw string values in UserDefaults to match what InteractiveBrokers expects
    @AppStorage("trading.mode") private var tradingModeRaw: String = TradingMode.paper.rawValue
    @AppStorage("connection.type") private var connectionTypeRaw: String = ConnectionType.gateway.rawValue
    @Environment(\.openURL) private var openURL
    @Environment(TradeManager.self) private var trades
    @State private var reconnecting: Bool = false
    @State private var reconnectTask: Task<Void, Never>? = nil
    @AppStorage("logging.enabled") private var loggingEnabled: Bool = false
    @AppStorage("logging.level") private var loggingLevelRaw: String = "debug"

    // Navigation selection state
    @State private var selectedSection: SettingsSection? = .general

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
    
    
    public init() {}
    
    // Helper function to create a section header
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.secondary)
            .padding(.top, 20)
            .padding(.bottom, 4)
    }
    
    // Helper function to create a setting row
    private func settingRow<Content: View>(
        title: String, 
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .frame(maxWidth: 200, alignment: .leading)
            Spacer()
            content()
                .frame(maxWidth: 250, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    public var body: some View {
        NavigationSplitView(sidebar: {
            List(SettingsSection.allCases, selection: $selectedSection) {
                section in
                NavigationLink(value: section) {
                    HStack {
                        Image(systemName: section.iconName)
                            .frame(width: 20)
                        Text(section.title)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .frame(minWidth: 180)
        }, detail: {
            // Main content area
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Conditional content based on selected section
                    if selectedSection == .general {
                        sectionHeader("Trading Environment")
                        Divider()
                        
                        settingRow(title: "Trading Mode") {
                            Picker("", selection: tradingMode) {
                                ForEach(TradingMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        settingRow(title: "Connection Type") {
                            Picker("", selection: connectionType) {
                                ForEach(ConnectionType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        settingRow(title: "Connection Control") {
                            HStack {
                                if reconnecting {
                                    ProgressView()
                                        .scaleEffect(0.75)
                                        .padding(.trailing, 8)
                                }
                                Button(reconnecting ? "Reconnecting…" : "Reconnect") {
                                    updateTradingConfiguration()
                                }
                                .keyboardShortcut(",", modifiers: [.command])
                                .disabled(reconnecting)
                            }
                        }
                    }
                    
                    if selectedSection == .status {
                        sectionHeader("Connection Status")
                        Divider()
                        
                        settingRow(title: "Provider") {
                            Text(String(describing: type(of: trades.market)))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        settingRow(title: "Last connect") {
                            if let t = trades.lastConnectTime {
                                Text(t, style: .relative)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("—")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        settingRow(title: "Status") {
                            Text(trades.lastConnectStatus ?? "—")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if selectedSection == .debug {
                        sectionHeader("Debug Options")
                        Divider()
                        
                        settingRow(title: "Stored trading.mode") {
                            Text(tradingModeRaw)
                                .foregroundColor(.secondary)
                        }
                        
                        settingRow(title: "Stored connection.type") {
                            Text(connectionTypeRaw)
                                .foregroundColor(.secondary)
                        }
                        
                        settingRow(title: "File Logging") {
                            Toggle(
                                isOn: Binding(
                                    get: { loggingEnabled },
                                    set: { v in
                                        loggingEnabled = v
                                        AppLog.setEnabled(v)
                                    })
                            ) {}
                        }
                        .help(
                            "Enable writing debug logs to ~/Library/Application Support/Swift&Smart/Logs/app.log"
                        )
                        
                        settingRow(title: "Log Level") {
                            Picker("", selection: Binding(
                                get: { loggingLevelRaw },
                                set: { newValue in
                                    loggingLevelRaw = newValue
                                    // Map the raw string to our LogLevel and update AppLog
                                    let lvl: LogLevel = 
                                        LogLevel(
                                            rawValue: ["debug", "info", "error"].firstIndex(
                                                of: newValue) ?? 0) ?? .debug
                                    AppLog.setFileLogLevel(lvl)
                                }
                            )) {
                                Text("Debug").tag("debug")
                                Text("Info").tag("info")
                                Text("Error").tag("error")
                            }
                            .frame(maxWidth: 150)
                        }
                        
                        if let url = AppLog.logFileURLPublic {
                            settingRow(title: "Log File") {
                                Button("Open") {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(minWidth: 500, minHeight: 300)
            }
        })
        .navigationSplitViewStyle(.balanced)
        .frame(width: 700, height: 450)
    }

    private func updateTradingConfiguration() {
        // Debounce rapid changes and trigger reconnection with new settings
        reconnectTask?.cancel()
        reconnectTask = Task { [tradingModeRaw, connectionTypeRaw] in
            // short debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                reconnecting = true
            }
            // initializeSockets() will cause TradeManager to ask InteractiveBrokers to recreate the client
            trades.initializeSockets()
            // leave the reconnect UI on briefly while the connection attempts
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                reconnecting = false
            }
        }
    }
}

#Preview {
    SettingsView()
}
