import SwiftUI
import Brokerage
import Runtime
import SwiftUIComponents

struct MessageView: View {
    @AppStorage("trade.alert.message.recipient") private var messageRecipient: String = ""
    @AppStorage("trade.alert.message.sms") private var isSMS: Bool = false
    @Environment(TradeManager.self) private var trades
    @State private var tempPhoneNumber: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Trade Alert Phone Number:")
                .font(.headline)
            TextField("Enter phone number", text: $tempPhoneNumber)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Checkbox(label: "SMS", checked: isSMS)
                .frame(height: 18)
                .contentShape(Rectangle())
                .onTapGesture {
                    isSMS.toggle()
                }
            if isSMS, !tempPhoneNumber.isValidPhoneNumber {
                Text("⚠️ Invalid phone number. Use format +1234567890.")
                    .foregroundColor(.red)
                    .font(.caption)
            } else if isSMS, !tempPhoneNumber.isValidPhoneNumberOrEmail {
                Text("⚠️ Invalid iMessage idenfitier.")
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                HStack {
                    if tempPhoneNumber != messageRecipient {
                        Button("Save Number") {
                            guard tempPhoneNumber.isValidPhoneNumber else { return }
                            messageRecipient = tempPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        .padding(.top, 5)
                    }
                    Button("Test") {
                        let bar = Bar(timeOpen: 0, interval: 0, priceOpen: 0, priceHigh: 0, priceLow: 0, priceClose: 0, volume: 0)
                        let trade = Trade(entryBar: bar, price: 1, stopPrice: 2, units: 3)
                        trades.tradeAlertHandler?.sendAlert(trade, recentBar: bar)
                    }
                    .padding(.top, 5)
                }
            }
        }
        .onAppear {
            tempPhoneNumber = messageRecipient
        }
    }
}
