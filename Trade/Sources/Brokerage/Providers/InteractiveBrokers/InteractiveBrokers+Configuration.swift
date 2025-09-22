import Foundation
import IBKit

public extension InteractiveBrokers {
    /// Reads account configuration from environment variables
    struct Configuration {
        /// The environment variable name for the account ID
        private static let accountIdEnvKey = "IB_ACCOUNT_ID"
        
        /// Get the account ID from environment variables
        /// - Returns: The account ID as a String if available, otherwise an empty string
        public static func getAccountId() -> String {
            return ProcessInfo.processInfo.environment[accountIdEnvKey] ?? ""
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