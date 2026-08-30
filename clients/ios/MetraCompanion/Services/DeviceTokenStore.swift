import Foundation
import Security

enum DeviceTokenStore {
    private static let service = "app.metra.companion.device"
    private static let account = "X-Metra-Device"

    /// Returns existing Keychain stub token or mints a local UUID stub (Phase 1).
    /// Replace with Ops WhoIs mint when tailscale-identity-auth ships.
    static func stubToken() -> String {
        if let existing = read() {
            return existing
        }
        let minted = "stub-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        _ = write(minted)
        return minted
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
}
