import SwiftUI
import WebKit

/// 微信读书 Web 登录页面
/// 使用 WKWebView 加载微信读书网页版，用户扫码登录后提取 Cookie
struct WeReadLoginView: View {
    @Environment(\.dismiss) private var dismiss
    let onLoginSuccess: (String) -> Void  // 回调传递 cookie 字符串

    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                WeReadWebView(
                    isLoading: $isLoading,
                    loadError: $loadError,
                    onLoginSuccess: { cookies in
                        onLoginSuccess(cookies)
                        dismiss()
                    }
                )

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("加载微信读书登录页...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .navigationTitle("登录微信读书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - WKWebView Wrapper

struct WeReadWebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    let onLoginSuccess: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()  // 不保留旧 session

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        // 加载微信读书登录页
        let url = URL(string: "https://weread.qq.com/#login")!
        webView.load(URLRequest(url: url))

        // 定时检查登录状态
        context.coordinator.startPolling(webView: webView)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WeReadWebView
        private var pollingTimer: Timer?
        private var hasLoggedIn = false
        private var isCheckingLogin = false  // 防止竞态条件

        /// 允许的域名白名单
        private let allowedHosts = ["weread.qq.com", "open.weixin.qq.com", "wx.qq.com"]

        init(parent: WeReadWebView) {
            self.parent = parent
        }

        deinit {
            pollingTimer?.invalidate()
        }

        func startPolling(webView: WKWebView) {
            // 每 2 秒检查一次 Cookie
            pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView, !self.hasLoggedIn else { return }
                self.checkLoginStatus(webView: webView)
            }
        }

        private func checkLoginStatus(webView: WKWebView) {
            // 防止竞态：上次检查还没完成时跳过
            guard !isCheckingLogin else { return }
            isCheckingLogin = true

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                defer { self.isCheckingLogin = false }
                guard !self.hasLoggedIn else { return }

                let wereadCookies = cookies.filter { $0.domain.contains("weread.qq.com") }
                let hasSkey = wereadCookies.contains { $0.name == "wr_skey" }
                let hasVid = wereadCookies.contains { $0.name == "wr_vid" }

                if hasSkey && hasVid {
                    self.hasLoggedIn = true
                    self.pollingTimer?.invalidate()

                    // 构造 cookie 字符串
                    let cookieString = wereadCookies
                        .map { "\($0.name)=\($0.value)" }
                        .joined(separator: "; ")

                    DispatchQueue.main.async {
                        self.parent.onLoginSuccess(cookieString)
                    }
                }
            }
        }

        // MARK: - WKNavigationDelegate

        /// SSL/域名验证 — 只允许 weread.qq.com 及微信相关域名
        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard let host = challenge.protectionSpace.host.lowercased() as String?,
                  allowedHosts.contains(where: { host.hasSuffix($0) }) else {
                // 非白名单域名，拒绝连接
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            // 对白名单域名使用系统默认 SSL 验证
            completionHandler(.performDefaultHandling, nil)
        }

        /// 导航策略 — 只允许加载白名单域名
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let host = navigationAction.request.url?.host?.lowercased(),
               allowedHosts.contains(where: { host.hasSuffix($0) }) {
                decisionHandler(.allow)
            } else if navigationAction.request.url?.scheme == "about" {
                decisionHandler(.allow)  // 允许 about:blank
            } else {
                decisionHandler(.cancel)  // 阻止跳转到非白名单域名
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.loadError = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = "加载失败: \(error.localizedDescription)"
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = "无法连接到微信读书，请检查网络"
            }
        }
    }
}
