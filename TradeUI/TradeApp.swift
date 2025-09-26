import AppKit
import Runtime
import SwiftUI
import TradeInterface

@main
struct TradeApp: App {
    @State private var trades: TradeManager

    init() {
        let trades = TradeManager(tradeAlertHandler: TradeAlertHandler())
        if let strategyFolder = UserDefaults.standard.string(forKey: "StrategyFolderPath") {
            trades.loadAllUserStrategies(into: StrategyRegistry.shared, location: strategyFolder)
        }

        _trades = State(initialValue: trades)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(trades)
                .environmentObject(StrategyRegistry.shared)
        } label: {
            let image: NSImage = {
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 18
                $0.size.width = 18 / ratio
                $0.isTemplate = true
                return $0
            }(NSImage(named: "MenuBarIcon")!)

            Image(nsImage: image)
                .renderingMode(.template)
                .foregroundColor(.primary)
        }

        Window(Bundle.main.displayName, id: "main") {
            ContentView()
                .environment(trades)
                .environmentObject(StrategyRegistry.shared)
                .onAppear {
                    trades.initializeSockets()
                }
        }

        WindowGroup("Watcher", for: Watcher.ID.self) { $watcherId in
            if let watcherId = watcherId, let watcher = trades.watchers[watcherId] {
                WatcherView(watcher: watcher)
                    .navigationTitle("Watcher: \(watcher.displayName)")
                    .environment(trades)
                    .environmentObject(StrategyRegistry.shared)
            }
        }

        WindowGroup("Snapshot Preview", for: FileSnapshotsView.ViewModel.SnapshotPreview.self) {
            $snapshot in
            if let node = snapshot?.file {
                SnapshotView(node: node, fileProvider: trades.fileProvider)
                    .environment(trades)
                    .environmentObject(StrategyRegistry.shared)
            }
        }

        WindowGroup("Snapshot Playback", for: FileSnapshotsView.ViewModel.SnapshotPlayback.self) {
            $snapshot in
            if let node = snapshot?.file {
                SnapshotPlaybackView(node: node, fileProvider: trades.fileProvider)
                    .environment(trades)
                    .environmentObject(StrategyRegistry.shared)
            }
        }

        Settings {
            SettingsView()
                .environment(trades)
                .environmentObject(StrategyRegistry.shared)
        }
        // App menu commands are provided in AppCommands.swift
    }
}
