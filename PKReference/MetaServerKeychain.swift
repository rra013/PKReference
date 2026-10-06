//
//  MetaServerKeychain.swift
//  PKReference
//
//  The PK Reference server's API key, in the Keychain rather than
//  UserDefaults, which is a plain file anyone with the device's backup can
//  read. It stays on this device: it isn't synced to iCloud, and it's
//  readable only after the device is first unlocked.
//

import Foundation
import Security

nonisolated enum MetaServerKeychain {
    static let service = "yukisoft.PKReference.metaServer"
    static let defaultAccount = "apiKey"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The saved key, or nil.
    static func read(account: String = defaultAccount) -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves `key`, replacing any saved one; a blank key removes it.
    @discardableResult
    static func save(_ key: String, account: String = defaultAccount) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return remove(account: account) }
        remove(account: account)
        var item = query(account)
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func remove(account: String = defaultAccount) -> Bool {
        let status = SecItemDelete(query(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
