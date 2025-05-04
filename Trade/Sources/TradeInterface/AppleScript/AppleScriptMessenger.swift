import Foundation

public struct AppleScriptMessenger {
    public static func run(_ message: String, recipient: String, isSMS: Bool) {
        guard let scriptPath = Bundle.module.path(
            forResource: isSMS ? "sms" : "imessage",
            ofType: "applescript"
        ) else {
            print("❌ AppleScript not found in bundle.")
            return
        }

        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = [scriptPath, recipient, message]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.launch()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print("📤 AppleScript Output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
}
