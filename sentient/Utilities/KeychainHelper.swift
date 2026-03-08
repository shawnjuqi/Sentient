import Foundation
import Security

/// Thin wrapper around the macOS Keychain for storing sensitive strings.
/// Uses kSecClassGenericPassword, which is the standard class for app secrets.
enum KeychainHelper {

    // MARK: - Identity

    /// Scopes every item to this app so keys don't collide with other apps.
    /// Bundle ID is unique per app, making it a safe namespace.
    private static let service = Bundle.main.bundleIdentifier ?? "com.sentient.app"

    // MARK: - Public API

    /// Writes `value` into the Keychain under `key`.
    /// Overwrites any previously stored value for the same key.
    static func save(_ value: String, key: String) {
        // Convert the string to raw bytes — the Keychain stores Data, not String.
        let data = Data(value.utf8)

        // Before adding, delete any existing item with the same service+key pair.
        // SecItemAdd will fail with errSecDuplicateItem if we skip this step.
        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword, // Item type: generic secret
            kSecAttrService: service,                  // Our app's namespace
            kSecAttrAccount: key                       // The logical name for this secret
        ]
        SecItemDelete(deleteQuery as CFDictionary)     // Ignore status; item may not exist yet

        // Now add the new value. kSecValueData is the actual encrypted payload.
        let addQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData:   data                      // The bytes to encrypt and store
        ]
        SecItemAdd(addQuery as CFDictionary, nil)      // nil = we don't need the result back
    }

    /// Reads the string stored under `key`, or returns nil if nothing is stored.
    static func load(key: String) -> String? {
        // Build a query that tells the Keychain exactly which item to fetch.
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  true,              // Tell Keychain to return the raw Data payload
            kSecMatchLimit:  kSecMatchLimitOne  // Only return the first (and only) match
        ]

        // SecItemCopyMatching writes the result into `result` via an inout pointer.
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        // errSecSuccess means the item was found and decrypted successfully.
        // Any other status (e.g. errSecItemNotFound) means we return nil.
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// Removes the item stored under `key`. Safe to call even if no item exists.
    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary) // Status ignored; deleting nonexistent item is fine
    }
}
