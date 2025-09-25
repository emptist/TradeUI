import SwiftUI

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings") {
                openWindow("settings")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
