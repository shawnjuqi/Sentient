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
    /// - Returns: `true` if the value was stored successfully.
    @discardableResult
    static func save(_ value: String, key: String) -> Bool {
        let data = Data(value.utf8)

        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData:   data
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            Log.error("Keychain save failed with status \(status)", category: "KeychainHelper")
        }
        return status == errSecSuccess
    }

    /// Reads the string stored under `key`, or returns nil if nothing is stored.
    static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// Removes the item stored under `key`. Safe to call even if no item exists.
    /// - Returns: `true` if the item was deleted or did not exist.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
