import Foundation

/// 从豆瓣获取图书简介和作者简介
/// 支持通过 ISBN 或书名+作者搜索
struct DoubanDescriptionFetcher {

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    // MARK: - 图书简介

    /// 通过 ISBN 获取图书简介
    func fetchBookDescription(isbn: String, title: String) async -> String? {
        if let desc = await fetchDescriptionFromDoubanISBN(isbn: isbn) {
            return desc
        }
        return await fetchBookDescriptionByTitle(title: title, author: nil)
    }

    /// 通过书名搜索获取图书简介
    func fetchBookDescriptionByTitle(title: String, author: String?) async -> String? {
        guard let doubanURL = await searchDoubanBookURL(title: title) else {
            return nil
        }
        return await fetchDescriptionFromDoubanPage(url: doubanURL, type: .book)
    }

    // MARK: - 作者简介

    /// 通过 ISBN 获取作者简介
    func fetchAuthorDescription(isbn: String, title: String) async -> String? {
        if let desc = await fetchAuthorDescFromDoubanISBN(isbn: isbn) {
            return desc
        }
        return await fetchAuthorDescriptionByTitle(title: title, author: nil)
    }

    /// 通过书名搜索获取作者简介
    func fetchAuthorDescriptionByTitle(title: String, author: String?) async -> String? {
        guard let doubanURL = await searchDoubanBookURL(title: title) else {
            return nil
        }
        return await fetchDescriptionFromDoubanPage(url: doubanURL, type: .author)
    }

    // MARK: - Private

    private enum DescriptionType {
        case book
        case author
    }

    private func fetchDescriptionFromDoubanISBN(isbn: String) async -> String? {
        guard let url = URL(string: "https://book.douban.com/isbn/\(isbn)/") else { return nil }
        guard let html = await fetchHTML(url: url) else { return nil }
        return extractBookDescription(from: html)
    }

    private func fetchAuthorDescFromDoubanISBN(isbn: String) async -> String? {
        guard let url = URL(string: "https://book.douban.com/isbn/\(isbn)/") else { return nil }
        guard let html = await fetchHTML(url: url) else { return nil }
        return extractAuthorDescription(from: html)
    }

    private func searchDoubanBookURL(title: String) async -> URL? {
        guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://book.douban.com/j/subject_suggest?q=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        // 全局豆瓣限速：保证至少 5 秒间隔
        await DoubanRateLimiter.shared.wait()

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        guard let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !results.isEmpty else {
            return nil
        }

        for result in results {
            guard result["type"] as? String == "b" else { continue }
            if let urlStr = result["url"] as? String, let bookURL = URL(string: urlStr) {
                return bookURL
            }
            if let id = result["id"] as? String {
                return URL(string: "https://book.douban.com/subject/\(id)/")
            }
        }

        return nil
    }

    private func fetchDescriptionFromDoubanPage(url: URL, type: DescriptionType) async -> String? {
        guard let html = await fetchHTML(url: url) else { return nil }
        switch type {
        case .book:
            return extractBookDescription(from: html)
        case .author:
            return extractAuthorDescription(from: html)
        }
    }

    private func fetchHTML(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        // 全局豆瓣限速：保证至少 5 秒间隔
        await DoubanRateLimiter.shared.wait()

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        // 防止异常大响应导致内存耗尽
        guard data.count <= 5_000_000 else { return nil }

        return String(data: data, encoding: .utf8)
    }

    private func extractBookDescription(from html: String) -> String? {
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

    private func extractAuthorDescription(from html: String) -> String? {
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

    private func cleanHTML(_ html: String) -> String? {
        let text = html.replacingOccurrences(of: "<[^>]{0,1000}>", with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
