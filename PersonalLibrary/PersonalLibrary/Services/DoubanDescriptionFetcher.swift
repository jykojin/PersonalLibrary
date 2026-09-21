import Foundation

/// 从豆瓣获取图书简介和作者简介
/// 支持通过 ISBN 或书名+作者搜索
struct DoubanDescriptionFetcher: Sendable {

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private let httpClient: any HTTPDataClient
    private let waitForRateLimit: @Sendable () async -> Void

    init(
        httpClient: any HTTPDataClient = URLSessionHTTPDataClient(),
        waitForRateLimit: @escaping @Sendable () async -> Void = {
            await DoubanRateLimiter.shared.wait()
        }
    ) {
        self.httpClient = httpClient
        self.waitForRateLimit = waitForRateLimit
    }

    func fetchBookPageByTitle(title: String, author: String?) async throws -> DoubanBookPage? {
        for doubanURL in try await searchDoubanBookURLs(title: title) {
            guard let html = try await fetchHTML(url: doubanURL),
                  let page = DoubanBookPage.parse(html) else {
                continue
            }
            if BookIdentityMatcher.matches(
                requestedTitle: title,
                requestedAuthor: author,
                candidateTitle: page.title,
                candidateAuthor: page.author
            ) {
                return page
            }
        }
        return nil
    }

    // MARK: - Private

    private func searchDoubanBookURLs(title: String) async throws -> [URL] {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://book.douban.com/j/subject_suggest?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        // 全局豆瓣限速：保证至少 5 秒间隔
        await waitForRateLimit()

        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 404 { return [] }
        guard httpResponse.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard data.count <= 5_000_000 else { throw HTTPDataClientError.responseTooLarge }

        guard let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !results.isEmpty else {
            return []
        }

        return Array(results.compactMap { result in
            guard result["type"] as? String == "b" else { return nil }
            if let urlStr = result["url"] as? String, let bookURL = URL(string: urlStr) {
                return Self.isAllowedBookURL(bookURL) ? bookURL : nil
            }
            if let id = result["id"] as? String {
                return URL(string: "https://book.douban.com/subject/\(id)/")
            }
            return nil
        }.prefix(5))
    }

    private static func isAllowedBookURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "book.douban.com"
            && url.user == nil
            && url.password == nil
            && url.fragment == nil
            && (url.port == nil || url.port == 443)
    }

    private func fetchHTML(url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        // 全局豆瓣限速：保证至少 5 秒间隔
        await waitForRateLimit()

        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 404 { return nil }
        guard httpResponse.statusCode == 200 else { throw URLError(.badServerResponse) }

        // 防止异常大响应导致内存耗尽
        guard data.count <= 5_000_000 else { throw HTTPDataClientError.responseTooLarge }

        return String(data: data, encoding: .utf8)
    }

    /// 从豆瓣页面 HTML 提取内容简介。优先取 `<span class="all hidden">` 里的完整正文，
    /// 只有页面没有该节点时才退回短版 —— 短版尾部会带 `(展开全部)` 锚点文本。
    /// 全 app 唯一的豆瓣简介解析实现，`ISBNLookupService` 也调这里（曾因两套实现不一致导致存了截断正文）。
    static func extractBookDescription(from html: String) -> String? {
        guard let introStart = html.range(of: "内容简介") else { return nil }
        let afterIntro = String(html[introStart.upperBound...])

        let introContent: String
        if let allHiddenRange = afterIntro.range(of: #"<span class="all hidden">"#),
           let divStart = afterIntro[allHiddenRange.upperBound...].range(of: #"<div class="intro">"#) {
            let afterDiv = String(afterIntro[divStart.upperBound...])
            if let divEnd = afterDiv.range(of: "</div>") {
                introContent = String(afterDiv[..<divEnd.lowerBound])
            } else {
                return nil
            }
        } else if let divStart = afterIntro.range(of: #"<div class="intro">"#) {
            let afterDiv = String(afterIntro[divStart.upperBound...])
            if let divEnd = afterDiv.range(of: "</div>") {
                introContent = String(afterDiv[..<divEnd.lowerBound])
            } else {
                return nil
            }
        } else {
            return nil
        }

        return cleanHTML(introContent)
    }

    /// 同上，作者简介。
    static func extractAuthorDescription(from html: String) -> String? {
        guard let introStart = html.range(of: "作者简介") else { return nil }
        let afterIntro = String(html[introStart.upperBound...])

        let introContent: String
        if let allHiddenRange = afterIntro.range(of: #"<span class="all hidden">"#),
           let divStart = afterIntro[allHiddenRange.upperBound...].range(of: #"<div class="intro">"#) {
            let afterDiv = String(afterIntro[divStart.upperBound...])
            if let divEnd = afterDiv.range(of: "</div>") {
                introContent = String(afterDiv[..<divEnd.lowerBound])
            } else {
                return nil
            }
        } else if let divStart = afterIntro.range(of: #"<div class="intro">"#) {
            let afterDiv = String(afterIntro[divStart.upperBound...])
            if let divEnd = afterDiv.range(of: "</div>") {
                introContent = String(afterDiv[..<divEnd.lowerBound])
            } else {
                return nil
            }
        } else {
            return nil
        }

        return cleanHTML(introContent)
    }

    static func cleanHTML(_ html: String) -> String? {
        let text = html.replacingOccurrences(of: "<[^>]{0,1000}>", with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
