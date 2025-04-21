import Foundation
import SwiftUI
import Brokerage
import Runtime
import TradingStrategy
import ForexFactory

extension DashboardView {
    @Observable class ViewModel {
        enum SidebarTab: String, CaseIterable {
            case watchers = "Account"
            case localFiles = "Local Files"

            var icon: String {
                switch self {
                case .watchers: return "case.fill"
                case .localFiles: return "folder"
                }
            }
        }
        
        var symbol = ""
        var suggestedSearches: [any Contract] = []
        var events: [ForexEvent] = []
        var selectedTab: SidebarTab = .watchers
        
        private var market: Market?
        
        @MainActor
        func loadProducts(symbol: String) async {
            guard let market = self.market else { return }
            do {
                try await loadProducts(market: market, symbol: symbol)
            } catch {
                print("🔴 Failed to suggest search with error:", error)
            }
        }
        
        func updateMarketData(_ market: Market) {
            self.market = market
        }
        
        @MainActor func chooseStrategyFolder(registry: StrategyRegistry) -> Bool {
            let dialog = NSOpenPanel()
            dialog.title = "Choose Strategy Folder"
            dialog.canChooseDirectories = true
            dialog.canChooseFiles = false
            dialog.allowsMultipleSelection = false

            if dialog.runModal() == .OK, let url = dialog.url {
                UserDefaults.standard.set(url.path, forKey: "StrategyFolderPath")
                return true
            }
            return false
        }
        
        @MainActor
        private func loadProducts(market: MarketSearch, symbol: Symbol) async throws {
            self.suggestedSearches = try await market.search(nameOrSymbol: symbol)
        }
        
        @MainActor
        func loadForexEvents() async -> [ForexEvent] {
            let cacheKey = "forexEventsCache"
            let lastFetchKey = "forexEventsLastFetch"
            
            // Check UserDefaults for cached events
            if let savedData = UserDefaults.standard.data(forKey: cacheKey),
               let lastFetchDate = UserDefaults.standard.object(forKey: lastFetchKey) as? Date,
               Calendar.current.isDateInToday(lastFetchDate) {
                
                do {
                    let cachedEvents = try JSONDecoder().decode([ForexEvent].self, from: savedData)
                    events = cachedEvents
                    print("✅ Loaded cached Forex events from UserDefaults.")
                    return cachedEvents
                } catch {
                    print("⚠️ Failed to decode cached Forex events, fetching new data.")
                }
            }

            // Fetch new data if no valid cache exists
            do {
                let newEvents = try await ForexAPI
                    .fetchEvents()
                    .eventsForToday()
                    .events(by: "USD")
                
                // Update the UI
                events = newEvents
                
                // Cache the new data
                let encodedData = try JSONEncoder().encode(newEvents)
                UserDefaults.standard.set(encodedData, forKey: cacheKey)
                UserDefaults.standard.set(Date(), forKey: lastFetchKey)

                print("✅ Fetched new Forex events and cached them.")
                return newEvents
            } catch {
                print("🔴 Failure fetching forex events:", error)
            }
            return []
        }
    }
}

// MARK: Types

extension ForexEvent: TradingStrategy.Annoucment {
    public var timestamp: TimeInterval {
        date.timeIntervalSince1970
    }
    
    public var annoucmentImpact: TradingStrategy.AnnoucmentImpact {
        switch impact {
        case .high: .high
        case .medium: .medium
        case .low: .low
        case .other: .low
        }
    }
}
