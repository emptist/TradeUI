import Foundation
import Runtime
import TradingStrategy
import AppKit
import SwiftUIComponents

public class TradeAlertHandler: TradeAlertHandling, @unchecked Sendable {
    public init() {}
    
    public func patternInformationChange(_ patternInformation: [String: Bool]) {}
    
    public func sendAlert(_ trade: Trade, recentBar: Klines) {
        if UserDefaults.standard.value(forKey: "trade.alert.sound") as? Bool ?? true {
            playSoundAlert()
        }
        if UserDefaults.standard.value(forKey: "trade.alert.message") as? Bool ?? true,
            let recipient = UserDefaults.standard.string(forKey: "trade.alert.message.recipient")?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if recipient.isValidPhoneNumber {
                let tradeDirection = trade.isLong ? "Long" : "Short"
                let message = "📈 Trade Alert: \(tradeDirection) at \(trade.price)\nRecent Bar: \(recentBar.priceClose)"
                sendiMessage(message, recipient: recipient)
            } else {
                print("❌ Invalid phone number: \(recipient)")
            }
        }
    }
    
    /**
     ✅ Ensures Messages is running before execution.
     ✅ Checks for an existing iMessage chat.
     ✅ Falls back to sending a message directly if chat creation fails.
     ✅ Prevents SMS fallback (only sends as iMessage).
     */
    
    /// Sends an iMessage or SMS notification when a trade entry/exit occurs
    /// - Parameters:
    ///   - message: message to be sent
    ///   - recipient: recipient phone number i.e. "+1234567890"
    private func sendiMessage(_ message: String, recipient: String) {
        let isSMS = UserDefaults.standard.value(forKey: "trade.alert.message.sms") as? Bool ?? false
        AppleScriptMessenger.run(message, recipient: recipient, isSMS: isSMS)
    }

    /// Plays a sound alert when a trade entry/exit occurs
    private func playSoundAlert() {
        SystemSound.glass.play()
    }
    
    // MARK: - Types
    
    public enum SystemSound: String, CaseIterable {
        case basso = "Basso"
        case blow = "Blow"
        case bottle = "Bottle"
        case frog = "Frog"
        case funk = "Funk"
        case glass = "Glass"
        case hero = "Hero"
        case morse = "Morse"
        case ping = "Ping"
        case pop = "Pop"
        case purr = "Purr"
        case sosumi = "Sosumi"
        case submarine = "Submarine"
        case tink = "Tink"

        /// Plays the selected system sound
        public func play() {
            NSSound(named: NSSound.Name(self.rawValue))?.play()
        }
    }
}

public extension String {
    var isValidPhoneNumber: Bool {
        let phoneRegex = #"^\+?[1-9]\d{1,14}$"#
        return NSPredicate(format: "SELF MATCHES %@", phoneRegex).evaluate(with: self)
    }

    var isValidEmail: Bool {
        let emailRegex = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return NSPredicate(format: "SELF MATCHES[c] %@", emailRegex).evaluate(with: self)
    }

    var isValidPhoneNumberOrEmail: Bool {
        isValidPhoneNumber || isValidEmail
    }
}
