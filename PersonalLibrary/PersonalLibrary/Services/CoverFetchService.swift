import Foundation
import SwiftData
import UIKit

// MARK: - 简易异步信号量（限制并发数）

/// 轻量级异步信号量，用于限制并发任务数
actor AsyncSemaphore {
    private let limit: Int
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
        self.count = limit
    }

    func wait() async {
        if count > 0 {
            count -= 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func signal() {
        if waiters.isEmpty {
            count = min(count + 1, limit)
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}

// MARK: - 封面内存缓存

/// UIImage 内存缓存，避免重复 Data→UIImage 解码
final class CoverImageCache: @unchecked Sendable {
    static let shared = CoverImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()

    init() {
        cache.countLimit = 200  // 最多缓存 200 张
        cache.totalCostLimit = 100 * 1024 * 1024  // 100MB 上限
    }

    func image(for key: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.setObject(image, forKey: key as NSString)
    }

    func remove(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeObject(forKey: key as NSString)
    }
}

// MARK: - 封面获取服务

/// 封面图片获取服务
/// 从豆瓣页面解析封面图片 URL，下载后缓存到本地
actor CoverFetchService {

    static let shared = CoverFetchService()

    private var inFlightRequests: Set<String> = []

    /// 并发控制：最多同时 3 个封面下载，防止滚动时网络风暴
    private let semaphore = AsyncSemaphore(limit: 3)

    /// 带并发限制的封面获取入口（供 BookRowView 调用）
    func fetchCoverThrottled(
        coverImageURL: String?,
        isbn: String?,
        doubanURL: String?,
        title: String?,
        author: String?
    ) async -> Data? {
        await semaphore.wait()
        defer { Task { await semaphore.signal() } }

        // 优先 coverImageURL 直接下载（需通过域名白名单校验）
        if let urlStr = coverImageURL, !urlStr.isEmpty, isAllowedDomain(urlStr) {
            let data = await downloadWithReferer(urlStr: urlStr)
            if let data, data.count > 100 {
                return data
            }
        }

        // 备用：豆瓣搜索 + Open Library
        return await fetchCover(isbn: isbn, doubanURL: doubanURL, title: title, author: author)
    }

    /// 从豆瓣链接获取封面图片数据
    func fetchCoverFromDouban(doubanURL: String) async -> Data? {
        guard let url = URL(string: doubanURL) else { return nil }

        // 防止重复请求
        guard !inFlightRequests.contains(doubanURL) else { return nil }
        inFlightRequests.insert(doubanURL)
        defer { inFlightRequests.remove(doubanURL) }

        do {
            // 必须用桌面 UA，移动端 UA 会被豆瓣重定向到 404
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            await DoubanRateLimiter.shared.wait()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                AppLogger.debug("Douban HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)", category: "CoverFetch")
                return nil
            }

            guard let html = String(data: data, encoding: .utf8) else { return nil }
            guard let imageURL = parseCoverImageURL(from: html) else {
                AppLogger.debug("No cover URL found in douban page", category: "CoverFetch")
                return nil
            }

            AppLogger.debug("Found cover URL: \(imageURL)", category: "CoverFetch")
            return await downloadImage(from: imageURL)
        } catch {
            AppLogger.warning("Error fetching douban page: \(error)", category: "CoverFetch")
            return nil
        }
    }

    /// 从 Open Library 获取封面
    func fetchCoverFromOpenLibrary(isbn: String) async -> Data? {
        let cleanISBN = isbn.replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression)
        guard cleanISBN.count == 10 || cleanISBN.count == 13 else { return nil }

        let urlStr = "https://covers.openlibrary.org/b/isbn/\(cleanISBN)-L.jpg"
        return await downloadImage(from: urlStr)
    }

    /// 尝试所有来源获取封面
    func fetchCover(isbn: String?, doubanURL: String?, title: String? = nil, author: String? = nil) async -> Data? {
        // 优先豆瓣页面解析（如果有链接）
        if let doubanURL, !doubanURL.isEmpty {
            if let data = await fetchCoverFromDouban(doubanURL: doubanURL) {
                return data
            }
        }

        // 豆瓣搜索 API（用书名搜索，中文书覆盖率高）
        if let title, !title.isEmpty {
            if let data = await fetchCoverFromDoubanSearch(title: title, author: author) {
                return data
            }
        }

        // 备用 Open Library
        if let isbn, !isbn.isEmpty {
            if let data = await fetchCoverFromOpenLibrary(isbn: isbn) {
                // Open Library 返回 1x1 pixel 表示没有封面，过滤小文件
                if data.count > 1000 {
                    return data
                }
            }
        }
        return nil
    }

    /// 通过豆瓣搜索建议 API 获取封面
    func fetchCoverFromDoubanSearch(title: String, author: String?) async -> Data? {
        // 清理书名：去掉括号内容（中英文括号），这些通常是用户自加的备注
        let cleanTitle = cleanSearchTitle(title)
        guard !cleanTitle.isEmpty else { return nil }

        // 先用清理后的书名搜索
        if let data = await searchDoubanCover(query: cleanTitle, originalTitle: title, author: author) {
            return data
        }

        // 如果清理后的标题和原标题不同，且第一次没搜到，尝试原标题
        if cleanTitle != title {
            return await searchDoubanCover(query: title, originalTitle: title, author: author)
        }

        return nil
    }

    /// 清理书名用于搜索：去掉括号及其内容
    private func cleanSearchTitle(_ title: String) -> String {
        var result = title
        // 去掉中文括号 （...）
        result = result.replacingOccurrences(of: #"（[^）]*）"#, with: "", options: .regularExpression)
        // 去掉英文括号 (...)
        result = result.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        // 去掉中文书名号内的副标题之后的部分不处理，只清理括号
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func searchDoubanCover(query: String, originalTitle: String, author: String?) async -> Data? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://book.douban.com/j/subject_suggest?q=\(encoded)") else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10

            await DoubanRateLimiter.shared.wait()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !results.isEmpty else {
                return nil
            }

            // 找到最匹配的结果
            let cleanQuery = cleanSearchTitle(originalTitle)
            var bestMatch: [String: Any]?
            for result in results {
                guard result["type"] as? String == "b" else { continue }
                let resultTitle = result["title"] as? String ?? ""
                // 完全匹配清理后的书名
                if resultTitle == cleanQuery || resultTitle == originalTitle {
                    if let author, !author.isEmpty {
                        let resultAuthor = result["author_name"] as? String ?? ""
                        if resultAuthor.contains(String(author.prefix(2))) {
                            bestMatch = result
                            break
                        }
                    }
                    bestMatch = result
                    break
                }
                // 部分包含匹配
                if bestMatch == nil && (resultTitle.contains(cleanQuery) || cleanQuery.contains(resultTitle)) {
                    bestMatch = result
                }
            }

            let match = bestMatch ?? results.first(where: { ($0["type"] as? String) == "b" }) ?? results[0]

            guard let picURL = match["pic"] as? String, !picURL.isEmpty else {
                return nil
            }

            // 将小图 URL (/s/) 替换为大图 (/l/)
            let largePicURL = picURL.replacingOccurrences(of: "/view/subject/s/", with: "/view/subject/l/")

            AppLogger.debug("Douban search found cover: \(largePicURL)", category: "CoverFetch")
            return await downloadImage(from: largePicURL)
        } catch {
            AppLogger.warning("Douban search error: \(error)", category: "CoverFetch")
            return nil
        }
    }

    /// 允许下载封面的域名白名单
    private static let allowedImageDomains = [
        "doubanio.com",
        "douban.com",
        "openlibrary.org",
        "googleapis.com",
        "books.google.com",
        "covers.openlibrary.org"
    ]

    /// 验证 URL 是否在允许的域名白名单内
    private func isAllowedDomain(_ urlStr: String) -> Bool {
        guard let url = URL(string: urlStr),
              let host = url.host?.lowercased(),
              url.scheme == "https" || url.scheme == "http" else {
            return false
        }
        return Self.allowedImageDomains.contains { host.hasSuffix($0) }
    }

    /// 下载豆瓣封面图片
    /// 将 lpic URL 转换为可用的 view/subject URL，并带 Referer 下载
    func downloadWithReferer(urlStr: String) async -> Data? {
        // 转换 URL: /lpic/sXXX.jpg → /view/subject/l/public/sXXX.jpg
        let convertedURL = convertDoubanCoverURL(urlStr)
        guard let url = URL(string: convertedURL),
              isAllowedDomain(convertedURL) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("https://book.douban.com/", forHTTPHeaderField: "Referer")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            return data
        } catch {
            AppLogger.warning("Direct download failed: \(error)", category: "CoverFetch")
            return nil
        }
    }

    /// 转换豆瓣封面 URL
    /// "https://img3.doubanio.com/lpic/s28688273.jpg" → "https://img3.doubanio.com/view/subject/l/public/s28688273.jpg"
    private func convertDoubanCoverURL(_ urlStr: String) -> String {
        if urlStr.contains("/lpic/") {
            return urlStr.replacingOccurrences(of: "/lpic/", with: "/view/subject/l/public/")
        }
        return urlStr
    }

    // MARK: - Private

    private func parseCoverImageURL(from html: String) -> String? {
        // 模式1: property="og:image" content="..."
        if let range = html.range(of: #"property="og:image"\s+content="([^"]+)""#, options: .regularExpression) {
            let matched = String(html[range])
            if let urlRange = matched.range(of: #"content="([^"]+)""#, options: .regularExpression) {
                var url = String(matched[urlRange])
                url = url.replacingOccurrences(of: "content=\"", with: "")
                url = url.replacingOccurrences(of: "\"", with: "")
                if url.hasPrefix("http") {
                    return url
                }
            }
        }

        // 模式2: content="..." property="og:image"
        if let range = html.range(of: #"content="(https?://[^"]+)" property="og:image""#, options: .regularExpression) {
            let matched = String(html[range])
            if let start = matched.range(of: "content=\"")?.upperBound,
               let end = matched.range(of: "\" property")?.lowerBound {
                let url = String(matched[start..<end])
                if url.hasPrefix("http") {
                    return url
                }
            }
        }

        // 模式3: 直接匹配豆瓣大图 URL
        if let range = html.range(of: #"https://img\d\.doubanio\.com/view/subject/l/public/s\d+\.jpg"#, options: .regularExpression) {
            return String(html[range])
        }

        return nil
    }

    /// 封面图片最大允许 5MB
    private static let maxImageSize = 5 * 1024 * 1024

    private func downloadImage(from urlStr: String) async -> Data? {
        guard let url = URL(string: urlStr) else { return nil }
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("https://book.douban.com", forHTTPHeaderField: "Referer")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                AppLogger.debug("Image download HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)", category: "CoverFetch")
                return nil
            }
            // 防止超大响应导致内存耗尽
            guard data.count <= Self.maxImageSize else {
                AppLogger.warning("Image too large: \(data.count) bytes, skipping", category: "CoverFetch")
                return nil
            }
            return data
        } catch {
            AppLogger.warning("Download failed: \(error)", category: "CoverFetch")
            return nil
        }
    }
}
