import Foundation
import IBKit

public extension InteractiveBrokers {
    /// Reads configuration values from environment variables
    /// This provides a more flexible way to configure the IB connection without modifying code
    struct Configuration {
        /// The default environment variable name for the account ID
        private static let accountIdEnvKey = "IB_ACCOUNT_ID"
        
        /// The default environment variable name for the host
        private static let hostEnvKey = "IB_HOST"
        
        /// The default environment variable name for the port
        private static let portEnvKey = "IB_PORT"
        
        /// Get the account ID from environment variables or return a default value
        /// - Returns: The account ID as a String
        public static func getAccountId() -> String {
            return ProcessInfo.processInfo.environment[accountIdEnvKey] ?? ""
        }
        
        /// Get the host from environment variables or return a default value
        /// - Returns: The host as a String
        public static func getHost() -> String {
            return ProcessInfo.processInfo.environment[hostEnvKey] ?? "127.0.0.1"
        }
        
        /// Get the port from environment variables or return a default value
        /// - Returns: The port as an Int
        public static func getPort() -> Int {
            guard let portString = ProcessInfo.processInfo.environment[portEnvKey],
                  let port = Int(portString)
            else {
                return 4002 // Default IB Gateway port
            }
            return port
        }
        
        /// Check if the account ID is set in environment variables
        /// - Returns: Boolean indicating if the account ID is set
        public static func isAccountIdConfigured() -> Bool {
            return !getAccountId().isEmpty
        }
    }
    
    /// Get the default account using environment configuration
    /// This method first checks for an account ID in environment variables, then falls back to the first available account
    /// - Returns: The default Account if available
    func getDefaultAccount() -> Account? {
        if Configuration.isAccountIdConfigured() {
            let accountId = Configuration.getAccountId()
            print("🔧 Using account from environment: \(accountId)")
            return getAccount(id: accountId)
        } else {
            // Fallback to the first available account
            return accounts.first?.value
        }
    }
}