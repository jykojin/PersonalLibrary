import Foundation
import UIKit

/// 微信 OAuth 认证管理器
/// 注意：需要在微信开放平台注册获取 AppID 和 AppSecret
/// 实际生产中，AppSecret 不应放在客户端，应通过后端服务器换取 token
class WeChatAuthManager {
    static let shared = WeChatAuthManager()

    // MARK: - 配置（需要替换为真实值）

    /// 微信开放平台 AppID — 在微信开放平台创建移动应用后获得
    /// 替换为你的真实 AppID
    private let appId = "wx_YOUR_APP_ID"

    /// 微信开放平台 AppSecret — 生产环境中应放在服务端！
    /// 这里仅做架构演示，正式发布前必须迁移到后端
    private let appSecret = "YOUR_APP_SECRET"

    /// Universal Link（微信要求 iOS 应用配置 Universal Link）
    private let universalLink = "https://your-domain.com/app/"

    // MARK: - 登录回调

    /// 登录成功后的回调（由 AppDelegate / SceneDelegate 调用）
    private var authCompletion: ((Result<String, WeChatAuthError>) -> Void)?

    private init() {}

    // MARK: - 检查微信是否安装

    /// 检查设备是否安装了微信
    var isWeChatInstalled: Bool {
        guard let url = URL(string: "weixin://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    // MARK: - 发起登录

    /// 发起微信 OAuth 授权请求
    /// 调用后会跳转到微信 App，用户授权后回调 handleOpenURL
    func requestAuth() async throws -> String {
        guard isWeChatInstalled else {
            throw WeChatAuthError.wechatNotInstalled
        }

        return try await withCheckedThrowingContinuation { continuation in
            authCompletion = { result in
                continuation.resume(with: result)
            }

            // 构造微信授权 URL
            let state = UUID().uuidString.prefix(16)
            let scope = "snsapi_userinfo"
            let urlString = "weixin://app/\(appId)/auth/?scope=\(scope)&state=\(state)"

            guard let url = URL(string: urlString) else {
                continuation.resume(throwing: WeChatAuthError.invalidURL)
                return
            }

            DispatchQueue.main.async {
                UIApplication.shared.open(url) { success in
                    if !success {
                        self.authCompletion = nil
                        continuation.resume(throwing: WeChatAuthError.cannotOpenWeChat)
                    }
                }
            }
        }
    }

    // MARK: - 处理回调

    /// 处理微信回调 URL（在 SceneDelegate 或 AppDelegate 中调用）
    /// - Parameter url: 微信回调的 URL，包含 code 参数
    /// - Returns: 是否成功处理
    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        // 微信回调 URL 格式: your-universal-link?code=xxxxx&state=xxxxx
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            authCompletion?(.failure(.invalidCallback))
            authCompletion = nil
            return false
        }

        authCompletion?(.success(code))
        authCompletion = nil
        return true
    }

    // MARK: - Token 换取

    struct TokenResult {
        let accessToken: String
        let refreshToken: String
        let openId: String
        let expiresIn: Int
    }

    /// 使用 authorization code 换取 access_token
    /// 注意：生产环境中此请求应在服务端完成！
    func exchangeToken(code: String) async throws -> TokenResult {
        let urlString = "https://api.weixin.qq.com/sns/oauth2/access_token?appid=\(appId)&secret=\(appSecret)&code=\(code)&grant_type=authorization_code"

        guard let url = URL(string: urlString) else {
            throw WeChatAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeChatAuthError.networkError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WeChatAuthError.invalidResponse
        }

        // 检查错误
        if let errcode = json["errcode"] as? Int, errcode != 0 {
            let errmsg = json["errmsg"] as? String ?? "未知错误"
            throw WeChatAuthError.apiError(code: errcode, message: errmsg)
        }

        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let openId = json["openid"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw WeChatAuthError.invalidResponse
        }

        // 保存 token 到 Keychain
        KeychainService.save(key: KeychainService.wechatTokenKey, string: accessToken)

        return TokenResult(
            accessToken: accessToken,
            refreshToken: refreshToken,
            openId: openId,
            expiresIn: expiresIn
        )
    }

    // MARK: - 获取用户信息

    struct WeChatUserInfo {
        let nickname: String
        let avatarURL: String?
        let sex: Int  // 1=男 2=女 0=未知
        let province: String?
        let city: String?
    }

    /// 获取微信用户信息
    func fetchUserInfo(accessToken: String, openId: String) async throws -> WeChatUserInfo {
        let urlString = "https://api.weixin.qq.com/sns/userinfo?access_token=\(accessToken)&openid=\(openId)&lang=zh_CN"

        guard let url = URL(string: urlString) else {
            throw WeChatAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeChatAuthError.networkError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WeChatAuthError.invalidResponse
        }

        if let errcode = json["errcode"] as? Int, errcode != 0 {
            let errmsg = json["errmsg"] as? String ?? "未知错误"
            throw WeChatAuthError.apiError(code: errcode, message: errmsg)
        }

        let nickname = json["nickname"] as? String ?? "微信用户"
        let headimgurl = json["headimgurl"] as? String
        let sex = json["sex"] as? Int ?? 0
        let province = json["province"] as? String
        let city = json["city"] as? String

        return WeChatUserInfo(
            nickname: nickname,
            avatarURL: headimgurl,
            sex: sex,
            province: province,
            city: city
        )
    }
}

// MARK: - Errors

enum WeChatAuthError: Error, LocalizedError {
    case wechatNotInstalled
    case cannotOpenWeChat
    case invalidURL
    case invalidCallback
    case networkError
    case invalidResponse
    case apiError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .wechatNotInstalled: return "未安装微信，请先安装微信"
        case .cannotOpenWeChat: return "无法打开微信"
        case .invalidURL: return "URL 构造失败"
        case .invalidCallback: return "微信回调无效"
        case .networkError: return "网络请求失败"
        case .invalidResponse: return "服务器响应无效"
        case .apiError(_, let message): return "微信接口错误: \(message)"
        }
    }
}
