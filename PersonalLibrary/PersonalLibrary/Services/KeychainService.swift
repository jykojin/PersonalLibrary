import Foundation
import Security

/// Keychain 封装 — 安全存储敏感数据（Cookie、Token 等）
struct KeychainService {

    /// 保存数据到 Keychain
    static func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: bundleIdentifier
        ]
        // 先删除旧数据
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// 保存字符串到 Keychain
    @discardableResult
    static func save(key: String, string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }

    /// 从 Keychain 读取数据
    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: bundleIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// 从 Keychain 读取字符串
    static func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 删除 Keychain 数据
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: bundleIdentifier
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Keys

    /// 微信读书 Cookie
    static let wereadCookieKey = "com.personallibrary.weread.cookies"

    /// 微信登录 Token
    static let wechatTokenKey = "com.personallibrary.wechat.token"

    /// 微信读书 Skill API Key
    static let wereadApiKey = "com.personallibrary.weread.apikey"

    // MARK: - Private

    private static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.example.PersonalLibrary"
    }
}
