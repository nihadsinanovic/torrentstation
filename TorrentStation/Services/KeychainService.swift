import Foundation
import Security

/// Shared constants for Keychain and App Group access across app and extensions
enum SharedConstants {
    /// Keychain access group for sharing credentials between app and extensions.
    /// Must match the Keychain Sharing capability in both targets.
    static let keychainAccessGroup = "frugi.torrentstation.shared"

    /// App Group identifier for sharing UserDefaults between app and extensions.
    static let appGroupID = "group.frugi.torrentstation.shared"

    /// Shared UserDefaults backed by the App Group container.
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}

actor KeychainService {
    static let shared = KeychainService()
    private let service = "com.torrentstation.credentials"
    private let accessGroup: String? = nil

    func save(key: String, data: Data) throws {
        var deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let group = accessGroup {
            deleteQuery[kSecAttrAccessGroup as String] = group
        }
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        if let group = accessGroup {
            addQuery[kSecAttrAccessGroup as String] = group
        }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func load(key: String) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        return result as? Data
    }

    func delete(key: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Typed Convenience

    func saveCredentials(_ creds: StoredCredentials) throws {
        let data = try JSONEncoder().encode(creds)
        try save(key: "credentials", data: data)
        // Also write to shared App Group UserDefaults for the Share Extension
        SharedConstants.sharedDefaults?.set(data, forKey: "credentials")
    }

    func loadCredentials() throws -> StoredCredentials? {
        guard let data = try load(key: "credentials") else { return nil }
        return try JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    func deleteCredentials() throws {
        try delete(key: "credentials")
        SharedConstants.sharedDefaults?.removeObject(forKey: "credentials")
    }
}

nonisolated struct StoredCredentials: Codable, Sendable {
    let config: ConnectionConfig
    let username: String
    let password: String
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let s): "Keychain save failed (status: \(s))"
        case .loadFailed(let s): "Keychain load failed (status: \(s))"
        case .deleteFailed(let s): "Keychain delete failed (status: \(s))"
        }
    }
}
