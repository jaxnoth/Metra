import Foundation
import Security

enum DeviceTokenStore {
    private static let service = "app.metra.companion.device"
    private static let account = "X-Metra-Device"

    /// True when the stored token is a local UUID stub (not host-minted).
    static func isStub(_ token: String?) -> Bool {
        guard let token, !token.isEmpty else { return true }
        return token.hasPrefix("stub-")
    }

    /// Returns existing Keychain token or mints a local UUID stub for pre-pair Ask smoke.
    /// Prefer `pairWithOps` (Settings) so WhoIs mints a real device capability token.
    static func stubToken() -> String {
        if let existing = read() {
            return existing
        }
        let minted = "stub-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        _ = write(minted)
        return minted
    }

    /// Token for Ops headers: Keychain value, or local stub if never paired.
    static func tokenForRequests() -> String {
        read() ?? stubToken()
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
