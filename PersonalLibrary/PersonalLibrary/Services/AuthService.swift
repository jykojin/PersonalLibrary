import Foundation
import SwiftUI

/// 用户信息
struct UserProfile: Codable {
    var nickname: String
    var avatarURL: String?
    var openId: String  // 微信 openid
    var loginDate: Date

    static let guest = UserProfile(nickname: "未登录", avatarURL: nil, openId: "", loginDate: Date())
}

/// 登录状态管理
@Observable
class AuthService {
    static let shared = AuthService()

    /// 当前用户（nil 表示未登录）
    private(set) var currentUser: UserProfile?

    /// 是否已登录
    var isLoggedIn: Bool { currentUser != nil }

    private let userProfileKey = "com.personallibrary.userprofile"

    private init() {
        loadCachedUser()
    }

    // MARK: - 微信登录

    /// 微信授权登录成功后调用
    func loginWithWeChat(code: String) async throws {
        // 使用 code 换取 access_token + openid
        // 注意：实际生产中，这步应该在你的后端服务器完成，避免暴露 AppSecret
        // 这里仅做客户端演示架构
        let tokenResult = try await WeChatAuthManager.shared.exchangeToken(code: code)

        // 获取用户信息
        let userInfo = try await WeChatAuthManager.shared.fetchUserInfo(
            accessToken: tokenResult.accessToken,
            openId: tokenResult.openId
        )

        let profile = UserProfile(
            nickname: userInfo.nickname,
            avatarURL: userInfo.avatarURL,
            openId: tokenResult.openId,
            loginDate: Date()
        )

        // 保存到 Keychain
        if let data = try? JSONEncoder().encode(profile) {
            KeychainService.save(key: userProfileKey, data: data)
        }

        await MainActor.run {
            self.currentUser = profile
        }
    }

    /// 退出登录
    func logout() {
        currentUser = nil
        KeychainService.delete(key: userProfileKey)
        KeychainService.delete(key: KeychainService.wechatTokenKey)
    }

    // MARK: - Private

    private func loadCachedUser() {
        guard let data = KeychainService.load(key: userProfileKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return
        }
        currentUser = profile
    }
}
