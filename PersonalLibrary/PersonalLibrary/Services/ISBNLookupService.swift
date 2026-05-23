import Foundation

/// ISBN 查询结果 — 从 API 返回的书籍信息
struct ISBNLookupResult {
    var title: String
    var author: String
    var publisher: String?
    var publishDate: String?
    var totalPages: Int?
    var price: String?
    var bookDescription: String?
    var authorDescription: String?
    var coverImageURL: String?
    var isbn: String
    var doubanURL: String?
}

/// ISBN 查询服务 — 通过 ISBN 自动获取书籍信息
/// 优先使用 Open Library API（免费、无需 API key）
actor ISBNLookupService {

    /// 通过 ISBN 查询书籍信息
    func lookup(isbn: String) async throws -> ISBNLookupResult? {
        // 清理 ISBN（去掉连字符和空格，X 统一大写）
        let cleanISBN = isbn
            .replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression)
            .uppercased()

        // 验证 ISBN 格式（10位或13位）
        guard cleanISBN.count == 10 || cleanISBN.count == 13 else {
            return nil  // 格式无效，不发起 API 请求
        }

        // 优先：豆瓣 ISBN 查询（中文书覆盖率最高）
        if let result = try await lookupFromDouban(isbn: cleanISBN) {
            return result
        }

        // 备选：Open Library API
        if let result = try await lookupFromOpenLibrary(isbn: cleanISBN) {
            return result
        }

        // 备选：Google Books API
        if let result = try await lookupFromGoogleBooks(isbn: cleanISBN) {
            return result
        }

        // 备选：Goodreads（英文书覆盖率高）
        if let result = try await lookupFromGoodreads(isbn: cleanISBN) {
            return result
        }

        return nil
    }

    // MARK: - 豆瓣 ISBN 查询

    private func lookupFromDouban(isbn: String) async throws -> ISBNLookupResult? {
        // 豆瓣 ISBN 跳转：/isbn/{ISBN}/ → 301 到书籍页面
        guard let url = URL(string: "https://book.douban.com/isbn/\(isbn)/") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        // 使用自动跟随重定向的 session
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("[ISBNLookup] Douban HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            return nil
        }

        // 防止异常大响应导致内存耗尽
        guard data.count <= 5_000_000 else { return nil }

        guard let html = String(data: data, encoding: .utf8) else { return nil }

        // 解析书名
        guard let title = extractPattern(#"property="v:itemreviewed">([^<]+)</span>"#, from: html),
              !title.isEmpty else {
            return nil
        }

        // 提取 info 区域
        let info = extractPattern(#"<div id="info"(.*?)</div>"#, from: html, options: .dotMatchesLineSeparators) ?? ""

        // 作者
        let author = extractDoubanAuthor(from: info) ?? "未知作者"

        // 出版社
        let publisher = extractPattern(#"出版社:</span>\s*<a[^>]*>([^<]+)</a>"#, from: info)
            ?? extractPattern(#"出版社:</span>\s*([^<\n]+)"#, from: info)?.trimmingCharacters(in: .whitespaces)

        // 出版年
        let publishYear = extractPattern(#"出版年:</span>\s*([^<\n]+)"#, from: info)?.trimmingCharacters(in: .whitespaces)

        // 页数
        let pagesStr = extractPattern(#"页数:</span>\s*([^<\n]+)"#, from: info)?.trimmingCharacters(in: .whitespaces)
        let totalPages = pagesStr.flatMap { Int($0) }

        // 定价
        let price = extractPattern(#"定价:</span>\s*([^<\n]+)"#, from: info)?.trimmingCharacters(in: .whitespaces)

        // 封面
        var coverURL = extractPattern(#"property="og:image"\s+content="([^"]+)""#, from: html)
        if coverURL == nil {
            coverURL = extractPattern(#"content="([^"]+)"\s+property="og:image""#, from: html)
        }

        // 简介
        let bookDescription = extractDoubanDescription(from: html)

        // 作者简介
        let authorDescription = extractDoubanAuthorDescription(from: html)

        // 豆瓣链接（最终跳转的 URL）
        let doubanURL = response.url?.absoluteString

        print("[ISBNLookup] Douban found: \(title) by \(author)")

        return ISBNLookupResult(
            title: title,
            author: author,
            publisher: publisher,
            publishDate: publishYear,
            totalPages: totalPages,
            price: price,
            bookDescription: bookDescription,
            authorDescription: authorDescription,
            coverImageURL: coverURL,
            isbn: isbn,
            doubanURL: doubanURL
        )
    }

    // MARK: - 豆瓣页面解析辅助方法

    private func extractPattern(_ pattern: String, from text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private func extractDoubanAuthor(from info: String) -> String? {
        // 找作者区域的链接文本
        guard let authorSection = info.range(of: "作者") else { return nil }
        let afterAuthor = String(info[authorSection.upperBound...])
        // 截取到下一个 span（出版社等）
        let endIndex = afterAuthor.range(of: "<span")?.lowerBound ?? afterAuthor.endIndex
        let authorArea = String(afterAuthor[..<endIndex])

        // 提取所有 <a> 标签内容
        var authors: [String] = []
        let pattern = #"<a[^>]*>([^<]+)</a>"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(authorArea.startIndex..., in: authorArea)
            let matches = regex.matches(in: authorArea, range: range)
            for match in matches {
                if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: authorArea) {
                    let name = String(authorArea[r]).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        authors.append(name)
                    }
                }
            }
        }

        return authors.isEmpty ? nil : authors.joined(separator: ", ")
    }

    private func extractDoubanDescription(from html: String) -> String? {
        // 找书籍简介 — 在 "内容简介" 后面的 intro div
        guard let introStart = html.range(of: "内容简介") else { return nil }
        let afterIntro = String(html[introStart.upperBound...])

        // 找到 class="intro" 的 div
        guard let divStart = afterIntro.range(of: #"<div class="intro">"#) else { return nil }
        let afterDiv = String(afterIntro[divStart.upperBound...])
        guard let divEnd = afterDiv.range(of: "</div>") else { return nil }
        let content = String(afterDiv[..<divEnd.lowerBound])

        // 去掉 HTML 标签，保留文本
        let text = content.replacingOccurrences(of: "<[^>]{0,1000}>", with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return text.isEmpty ? nil : text
    }

    private func extractDoubanAuthorDescription(from html: String) -> String? {
        // 找作者简介
        guard let introStart = html.range(of: "作者简介") else { return nil }
        let afterIntro = String(html[introStart.upperBound...])

        guard let divStart = afterIntro.range(of: #"<div class="intro">"#) else { return nil }
        let afterDiv = String(afterIntro[divStart.upperBound...])
        guard let divEnd = afterDiv.range(of: "</div>") else { return nil }
        let content = String(afterDiv[..<divEnd.lowerBound])

        let text = content.replacingOccurrences(of: "<[^>]{0,1000}>", with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return text.isEmpty ? nil : text
    }

    // MARK: - Open Library API

    private func lookupFromOpenLibrary(isbn: String) async throws -> ISBNLookupResult? {
        let urlString = "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10  // 10秒超时
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bookData = json["ISBN:\(isbn)"] as? [String: Any] else {
            return nil
        }

        let title = bookData["title"] as? String ?? ""
        guard !title.isEmpty else { return nil }

        // 作者
        let authors = bookData["authors"] as? [[String: Any]] ?? []
        let authorName = authors.first?["name"] as? String ?? "未知作者"

        // 出版社
        let publishers = bookData["publishers"] as? [[String: Any]] ?? []
        let publisher = publishers.first?["name"] as? String

        // 出版日期
        let publishDate = bookData["publish_date"] as? String

        // 页数
        let pages = bookData["number_of_pages"] as? Int

        // 封面
        let cover = bookData["cover"] as? [String: Any]
        let coverURL = cover?["large"] as? String ?? cover?["medium"] as? String

        // 获取简介：需要从 Works API 获取
        var description: String?
        if let bookKey = bookData["key"] as? String {
            description = await fetchOpenLibraryDescription(bookKey: bookKey)
        }

        return ISBNLookupResult(
            title: title,
            author: authorName,
            publisher: publisher,
            publishDate: publishDate,
            totalPages: pages,
            price: nil,
            bookDescription: description,
            authorDescription: nil,
            coverImageURL: coverURL ?? "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg",
            isbn: isbn
        )
    }

    /// 从 Open Library Edition → Works 获取简介
    private func fetchOpenLibraryDescription(bookKey: String) async -> String? {
        // bookKey 格式: "/books/OL26818690M"，需要先获取 works key
        guard let editionURL = URL(string: "https://openlibrary.org\(bookKey).json") else { return nil }

        var request = URLRequest(url: editionURL)
        request.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Edition 本身可能有 description
        if let desc = json["description"] as? String, !desc.isEmpty { return desc }
        if let descObj = json["description"] as? [String: Any],
           let value = descObj["value"] as? String, !value.isEmpty { return value }

        // 否则去 Works 层级找
        guard let works = json["works"] as? [[String: Any]],
              let workKey = works.first?["key"] as? String,
              let workURL = URL(string: "https://openlibrary.org\(workKey).json") else {
            return nil
        }

        var workRequest = URLRequest(url: workURL)
        workRequest.timeoutInterval = 10
        guard let (workData, _) = try? await URLSession.shared.data(for: workRequest),
              let workJson = try? JSONSerialization.jsonObject(with: workData) as? [String: Any] else {
            return nil
        }

        if let desc = workJson["description"] as? String, !desc.isEmpty { return desc }
        if let descObj = workJson["description"] as? [String: Any],
           let value = descObj["value"] as? String, !value.isEmpty { return value }

        return nil
    }

    // MARK: - Google Books API

    private func lookupFromGoogleBooks(isbn: String) async throws -> ISBNLookupResult? {
        let urlString = "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10  // 10秒超时
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let firstItem = items.first,
              let volumeInfo = firstItem["volumeInfo"] as? [String: Any] else {
            return nil
        }

        let title = volumeInfo["title"] as? String ?? ""
        guard !title.isEmpty else { return nil }

        let authors = volumeInfo["authors"] as? [String] ?? []
        let authorName = authors.joined(separator: ", ")

        let publisher = volumeInfo["publisher"] as? String
        let publishDate = volumeInfo["publishedDate"] as? String
        let pages = volumeInfo["pageCount"] as? Int
        let description = volumeInfo["description"] as? String

        // 封面
        let imageLinks = volumeInfo["imageLinks"] as? [String: Any]
        let coverURL = imageLinks?["thumbnail"] as? String

        // 价格
        let saleInfo = firstItem["saleInfo"] as? [String: Any]
        let listPrice = saleInfo?["listPrice"] as? [String: Any]
        var price: String?
        if let amount = listPrice?["amount"] as? Double,
           let currency = listPrice?["currencyCode"] as? String {
            price = "\(currency) \(amount)"
        }

        return ISBNLookupResult(
            title: title,
            author: authorName.isEmpty ? "未知作者" : authorName,
            publisher: publisher,
            publishDate: publishDate,
            totalPages: pages,
            price: price,
            bookDescription: description,
            authorDescription: nil,
            coverImageURL: coverURL,
            isbn: isbn
        )
    }

    // MARK: - Goodreads

    private func lookupFromGoodreads(isbn: String) async throws -> ISBNLookupResult? {
        guard let url = URL(string: "https://www.goodreads.com/book/isbn/\(isbn)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        // 防止异常大响应
        guard data.count <= 5_000_000 else { return nil }

        guard let html = String(data: data, encoding: .utf8) else { return nil }

        // 从 JSON-LD 提取结构化数据
        guard let jsonLD = extractGoodreadsJsonLD(from: html) else { return nil }

        let title = jsonLD["name"] as? String ?? ""
        guard !title.isEmpty else { return nil }

        // 作者
        var authorName = "未知作者"
        if let authorObj = jsonLD["author"] as? [[String: Any]],
           let firstAuthor = authorObj.first,
           let name = firstAuthor["name"] as? String {
            authorName = name
        } else if let authorObj = jsonLD["author"] as? [String: Any],
                  let name = authorObj["name"] as? String {
            authorName = name
        }

        // 页数
        let pages = (jsonLD["numberOfPages"] as? Int)
            ?? (jsonLD["numberOfPages"] as? String).flatMap { Int($0) }

        // ISBN
        let bookISBN = jsonLD["isbn"] as? String ?? isbn

        // 描述
        let description = extractGoodreadsDescription(from: html)

        // 封面
        let coverURL = extractPattern(#"property="og:image"\s+content="([^"]+)""#, from: html)
            ?? extractPattern(#"content="([^"]+)"\s+property="og:image""#, from: html)

        print("[ISBNLookup] Goodreads found: \(title) by \(authorName)")

        return ISBNLookupResult(
            title: title,
            author: authorName,
            publisher: nil,
            publishDate: nil,
            totalPages: pages,
            price: nil,
            bookDescription: description,
            authorDescription: nil,
            coverImageURL: coverURL,
            isbn: bookISBN
        )
    }

    /// 从 Goodreads 页面提取 JSON-LD 结构化数据
    private func extractGoodreadsJsonLD(from html: String) -> [String: Any]? {
        let pattern = #"<script type="application/ld\+json">\s*(\{[^<]{0,50000})\s*</script>"#
        guard let jsonStr = extractPattern(pattern, from: html, options: .dotMatchesLineSeparators) else {
            return nil
        }
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// 从 Goodreads 页面提取图书描述
    private func extractGoodreadsDescription(from html: String) -> String? {
        // 方法1: 从 BookPageMetadataSection__description 区域提取
        let descPattern = #"BookPageMetadataSection__description[^>]{0,200}>.*?<span[^>]{0,200}class="[^"]*Formatted[^"]*"[^>]{0,100}>(.*?)</span>"#
        if let descHTML = extractPattern(descPattern, from: html, options: .dotMatchesLineSeparators) {
            let cleaned = cleanHTMLTags(descHTML)
            if !cleaned.isEmpty { return cleaned }
        }

        // 方法2: 从 JSON-LD description 字段
        let ldPattern = #""description"\s*:\s*"([^"]{1,5000})""#
        if let desc = extractPattern(ldPattern, from: html) {
            let unescaped = desc
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\/", with: "/")
            if !unescaped.isEmpty { return unescaped }
        }

        return nil
    }

    /// 去除 HTML 标签，保留文本
    private func cleanHTMLTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]{0,1000}>", with: "\n", options: .regularExpression)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - 封面图片下载

    /// 下载封面图片数据
    func downloadCoverImage(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
