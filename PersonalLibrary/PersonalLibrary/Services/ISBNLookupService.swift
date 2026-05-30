import Foundation

// MARK: - 豆瓣请求限速器

/// 豆瓣请求限速器（全局共享）— 保证所有豆瓣请求间隔至少 5 秒
/// 防止并发批量补全时被豆瓣封 IP
actor DoubanRateLimiter {
    static let shared = DoubanRateLimiter()
    private var lastRequestTime: Date = .distantPast
    private let minInterval: TimeInterval = 5.0

    func wait() async {
        let now = Date()
        let nextAllowed = max(now, lastRequestTime.addingTimeInterval(minInterval))
        lastRequestTime = nextAllowed     // reserve synchronously, before any await
        let delay = nextAllowed.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
    }
}

// MARK: - 智能补全数据源状态

/// 单个数据源的查询状态
enum LookupSourceStatus: Equatable {
    case notAttempted       // 未尝试（如没有ISBN则跳过ISBN类查询）
    case found             // 找到数据
    case notFound          // 查询成功但没有数据
    case error(String)     // 查询出错

    var displayText: String {
        switch self {
        case .notAttempted: return "未尝试"
        case .found: return "已找到"
        case .notFound: return "未找到"
        case .error(let msg): return "出错: \(msg)"
        }
    }
}

/// 智能补全结果 — 包含每个数据源的状态和最终填充的字段
struct SmartFillResult {
    /// 每个源的查询状态
    var sourceStatuses: [(name: String, status: LookupSourceStatus)]

    /// 补全到的字段值（nil 表示未能补全该字段）
    var title: String?
    var publisher: String?
    var totalPages: Int?
    var price: String?
    var publishDate: String?
    var translator: String?
    var author: String?
    var bookDescription: String?
    var authorDescription: String?

    /// 是否有任何字段被成功补全
    var hasAnyFill: Bool {
        title != nil || publisher != nil || totalPages != nil || price != nil
            || publishDate != nil || translator != nil || author != nil
            || bookDescription != nil || authorDescription != nil
    }
}

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

        // 全局豆瓣限速：保证至少 5 秒间隔，防止并发批量补全被封 IP
        await DoubanRateLimiter.shared.wait()

        // 使用自动跟随重定向的 session
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            AppLogger.debug("Douban HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)", category: "ISBNLookup")
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

        AppLogger.info("Douban found: \(title) by \(author)", category: "ISBNLookup")

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

    /// 从 Open Library 获取作者简介
    private func fetchOpenLibraryAuthorBio(authorKey: String) async -> String? {
        guard let url = URL(string: "https://openlibrary.org/authors/\(authorKey).json") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let bio = json["bio"] as? String, !bio.isEmpty { return bio }
        if let bioObj = json["bio"] as? [String: Any],
           let value = bioObj["value"] as? String, !value.isEmpty { return value }
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

        AppLogger.info("Goodreads found: \(title) by \(authorName)", category: "ISBNLookup")

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

    /// 通过书名搜索 Goodreads（无 ISBN 时使用）
    private func searchGoodreadsByTitle(title: String, author: String) async -> ISBNLookupResult? {
        let query = author.isEmpty || author == "未知作者" ? title : "\(title) \(author)"
        guard var components = URLComponents(string: "https://www.goodreads.com/search") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              data.count <= 5_000_000,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        // 从搜索结果页提取第一本书的链接
        let linkPattern = #"/book/show/(\d+)"#
        guard let bookPath = extractPattern(linkPattern, from: html) else { return nil }

        // 访问书籍详情页
        guard let bookURL = URL(string: "https://www.goodreads.com/book/show/\(bookPath)") else { return nil }
        var bookRequest = URLRequest(url: bookURL)
        bookRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        bookRequest.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        bookRequest.timeoutInterval = 15

        guard let (bookData, bookResp) = try? await URLSession.shared.data(for: bookRequest),
              let bookHttpResp = bookResp as? HTTPURLResponse,
              bookHttpResp.statusCode == 200,
              bookData.count <= 5_000_000,
              let bookHTML = String(data: bookData, encoding: .utf8) else {
            return nil
        }

        // 复用现有解析逻辑
        guard let jsonLD = extractGoodreadsJsonLD(from: bookHTML) else { return nil }

        let bookTitle = jsonLD["name"] as? String ?? ""
        guard !bookTitle.isEmpty else { return nil }

        var authorName = "未知作者"
        if let authorObj = jsonLD["author"] as? [[String: Any]],
           let firstAuthor = authorObj.first,
           let name = firstAuthor["name"] as? String {
            authorName = name
        } else if let authorObj = jsonLD["author"] as? [String: Any],
                  let name = authorObj["name"] as? String {
            authorName = name
        }

        let pages = (jsonLD["numberOfPages"] as? Int)
            ?? (jsonLD["numberOfPages"] as? String).flatMap { Int($0) }

        let description = extractGoodreadsDescription(from: bookHTML)

        AppLogger.info("Goodreads(title search) found: \(bookTitle) by \(authorName)", category: "ISBNLookup")

        return ISBNLookupResult(
            title: bookTitle,
            author: authorName,
            publisher: nil,
            publishDate: nil,
            totalPages: pages,
            price: nil,
            bookDescription: description,
            authorDescription: nil,
            coverImageURL: nil,
            isbn: jsonLD["isbn"] as? String ?? ""
        )
    }

    // MARK: - 智能补全（手动触发）

    /// 智能补全缺失字段 — 逐源查询，记录每个源的状态
    /// 只补全：出版社、页数、作者、图书简介、作者简介
    /// - Parameters:
    ///   - isbn: ISBN（可为空）
    ///   - title: 书名
    ///   - author: 当前作者值（为空则需补全）
    ///   - needsTitle: 是否需要书名
    ///   - needsPublisher: 是否需要出版社
    ///   - needsPages: 是否需要页数
    ///   - needsPrice: 是否需要定价
    ///   - needsPublishDate: 是否需要出版日期
    ///   - needsTranslator: 是否需要译者
    ///   - needsAuthor: 是否需要作者
    ///   - needsBookDesc: 是否需要图书简介
    ///   - needsAuthorDesc: 是否需要作者简介
    func smartFill(
        isbn: String,
        title: String,
        author: String,
        needsTitle: Bool = false,
        needsPublisher: Bool,
        needsPages: Bool,
        needsPrice: Bool = false,
        needsPublishDate: Bool = false,
        needsTranslator: Bool = false,
        needsAuthor: Bool,
        needsBookDesc: Bool,
        needsAuthorDesc: Bool
    ) async -> SmartFillResult {
        var result = SmartFillResult(sourceStatuses: [])

        let hasISBN = !isbn.isEmpty
        let cleanISBN = isbn
            .replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression)
            .uppercased()
        let validISBN = hasISBN && (cleanISBN.count == 10 || cleanISBN.count == 13)

        // 定义要查询的源
        // Note: Google Books removed from smartFill — empirically 0% hit rate on 800+ paper books,
        // pure CPU/network waste. lookup(isbn:) below still uses it for single-book add flow.
        let sources: [(name: String, lookup: () async -> ISBNLookupResult?)] = [
            ("豆瓣", { [self] in validISBN ? (try? await self.lookupFromDouban(isbn: cleanISBN)) : nil }),
            ("Open Library", { [self] in validISBN ? (try? await self.lookupFromOpenLibrary(isbn: cleanISBN)) : nil }),
            ("Goodreads", { [self] in validISBN ? (try? await self.lookupFromGoodreads(isbn: cleanISBN)) : nil })
        ]

        for source in sources {
            if !validISBN {
                result.sourceStatuses.append((name: source.name, status: .notAttempted))
                continue
            }

            // 检查是否还有未填充的字段
            let stillNeeds = (needsTitle && result.title == nil)
                || (needsPublisher && result.publisher == nil)
                || (needsPages && result.totalPages == nil)
                || (needsPrice && result.price == nil)
                || (needsPublishDate && result.publishDate == nil)
                || (needsTranslator && result.translator == nil)
                || (needsAuthor && result.author == nil)
                || (needsBookDesc && result.bookDescription == nil)
                || (needsAuthorDesc && result.authorDescription == nil)

            guard stillNeeds else {
                result.sourceStatuses.append((name: source.name, status: .notAttempted))
                continue
            }

            let t0 = CFAbsoluteTimeGetCurrent()
            let lookupResult = await source.lookup()
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            AppLogger.perf("smartFill source=\(source.name) elapsed=\(elapsedMs)ms hit=\(lookupResult != nil)", category: "ISBNLookup")

            if let lr = lookupResult {
                var foundSomething = false

                if needsTitle && result.title == nil,
                   !lr.title.isEmpty {
                    result.title = lr.title
                    foundSomething = true
                }
                if needsPublisher && result.publisher == nil,
                   let p = lr.publisher, !p.isEmpty {
                    result.publisher = p
                    foundSomething = true
                }
                if needsPages && result.totalPages == nil,
                   let p = lr.totalPages, p > 0 {
                    result.totalPages = p
                    foundSomething = true
                }
                if needsPrice && result.price == nil,
                   let p = lr.price, !p.isEmpty {
                    result.price = p
                    foundSomething = true
                }
                if needsPublishDate && result.publishDate == nil,
                   let d = lr.publishDate, !d.isEmpty {
                    result.publishDate = d
                    foundSomething = true
                }
                if needsTranslator && result.translator == nil {
                    // ISBNLookupResult 目前不带 translator，豆瓣有但需要从 HTML 额外提取
                    // 暂不填充 translator（留给未来扩展）
                }
                if needsAuthor && result.author == nil,
                   !lr.author.isEmpty, lr.author != "未知作者" {
                    result.author = lr.author
                    foundSomething = true
                }
                if needsBookDesc && result.bookDescription == nil,
                   let d = lr.bookDescription, !d.isEmpty {
                    result.bookDescription = d
                    foundSomething = true
                }
                if needsAuthorDesc && result.authorDescription == nil,
                   let d = lr.authorDescription, !d.isEmpty {
                    result.authorDescription = d
                    foundSomething = true
                }

                result.sourceStatuses.append((
                    name: source.name,
                    status: foundSomething ? .found : .notFound
                ))
            } else {
                result.sourceStatuses.append((name: source.name, status: .notFound))
            }
        }

        // 如果 ISBN 无效但有书名，尝试用书名搜索
        if !validISBN && !title.isEmpty {
            // 1. Open Library 书名搜索（无反爬，可靠，含作者简介）
            if (needsBookDesc && result.bookDescription == nil) || (needsAuthorDesc && result.authorDescription == nil) {
                let tOL0 = CFAbsoluteTimeGetCurrent()
                let olResult = await searchOpenLibraryByTitle(title: title, author: author.isEmpty || author == "未知作者" ? nil : author)
                let olElapsedMs = Int((CFAbsoluteTimeGetCurrent() - tOL0) * 1000)
                AppLogger.perf("smartFill source=OL(title) elapsed=\(olElapsedMs)ms hit=\(olResult != nil)", category: "ISBNLookup")
                var olFound = false
                if needsBookDesc && result.bookDescription == nil,
                   let desc = olResult?.bookDescription, !desc.isEmpty {
                    result.bookDescription = desc
                    olFound = true
                }
                if needsAuthorDesc && result.authorDescription == nil,
                   let desc = olResult?.authorDescription, !desc.isEmpty {
                    result.authorDescription = desc
                    olFound = true
                }
                result.sourceStatuses.append((
                    name: "Open Library(书名搜索)",
                    status: olFound ? .found : .notFound
                ))
            }

            // 2. Goodreads 书名搜索（英文书覆盖率高，可能被 WAF 拦截）
            if (needsBookDesc && result.bookDescription == nil) {
                let tGR0 = CFAbsoluteTimeGetCurrent()
                let grResult = await searchGoodreadsByTitle(title: title, author: author)
                let grElapsedMs = Int((CFAbsoluteTimeGetCurrent() - tGR0) * 1000)
                AppLogger.perf("smartFill source=Goodreads(title) elapsed=\(grElapsedMs)ms hit=\(grResult != nil)", category: "ISBNLookup")
                var grFound = false
                if needsBookDesc && result.bookDescription == nil,
                   let desc = grResult?.bookDescription, !desc.isEmpty {
                    result.bookDescription = desc
                    grFound = true
                }
                result.sourceStatuses.append((
                    name: "Goodreads(书名搜索)",
                    status: grFound ? .found : .notFound
                ))
            }

            // 3. 豆瓣书名搜索
            let fetcher = DoubanDescriptionFetcher()
            var foundSomething = false
            let tDB0 = CFAbsoluteTimeGetCurrent()

            if needsBookDesc && result.bookDescription == nil {
                let desc = await fetcher.fetchBookDescriptionByTitle(title: title, author: author)
                if let desc, !desc.isEmpty {
                    result.bookDescription = desc
                    foundSomething = true
                }
            }
            if needsAuthorDesc && result.authorDescription == nil {
                let desc = await fetcher.fetchAuthorDescriptionByTitle(title: title, author: author)
                if let desc, !desc.isEmpty {
                    result.authorDescription = desc
                    foundSomething = true
                }
            }

            let dbElapsedMs = Int((CFAbsoluteTimeGetCurrent() - tDB0) * 1000)
            AppLogger.perf("smartFill source=Douban(title) elapsed=\(dbElapsedMs)ms hit=\(foundSomething)", category: "ISBNLookup")

            result.sourceStatuses.append((
                name: "豆瓣(书名搜索)",
                status: foundSomething ? .found : .notFound
            ))
        }

        return result
    }

    // MARK: - 书名搜索（无 ISBN 时使用）

    /// 通过书名搜索 Open Library
    func searchOpenLibraryByTitle(title: String, author: String?) async -> ISBNLookupResult? {
        // 先用完整标题搜索，0 结果时用主标题（冒号/破折号前的部分）重试
        if let result = await searchOpenLibraryByTitleOnce(title: title, author: author) {
            return result
        }
        // 降级：截取主标题重试
        let separators: [Character] = [":", "：", "—", "–", "｜", "|"]
        if let idx = title.firstIndex(where: { separators.contains($0) }) {
            let mainTitle = String(title[..<idx]).trimmingCharacters(in: .whitespaces)
            if !mainTitle.isEmpty && mainTitle != title {
                AppLogger.warning("OL title search: retry with mainTitle=\(mainTitle)", category: "ISBNLookup")
                return await searchOpenLibraryByTitleOnce(title: mainTitle, author: author)
            }
        }
        return nil
    }

    private func searchOpenLibraryByTitleOnce(title: String, author: String?) async -> ISBNLookupResult? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        var queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "limit", value: "3")
        ]
        if let author, !author.isEmpty {
            queryItems.append(URLQueryItem(name: "author", value: author))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            AppLogger.warning("OL title search: URL build failed", category: "ISBNLookup")
            return nil
        }

        AppLogger.warning("OL title search: \(url.absoluteString)", category: "ISBNLookup")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.warning("OL title search: not HTTPURLResponse", category: "ISBNLookup")
                return nil
            }
            AppLogger.warning("OL title search: HTTP \(httpResponse.statusCode), bytes=\(data.count)", category: "ISBNLookup")
            guard httpResponse.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let docs = json["docs"] as? [[String: Any]] else {
                AppLogger.warning("OL title search: JSON parse failed or no docs array", category: "ISBNLookup")
                return nil
            }
            AppLogger.warning("OL title search: \(docs.count) docs found", category: "ISBNLookup")
            guard let firstDoc = docs.first else { return nil }

            let resultTitle = firstDoc["title"] as? String ?? title
            let authors = firstDoc["author_name"] as? [String] ?? []
            let authorName = authors.first ?? "未知作者"
            let publisher = (firstDoc["publisher"] as? [String])?.first
            let pages = firstDoc["number_of_pages_median"] as? Int
            let publishYear = (firstDoc["publish_year"] as? [Int])?.first.map { String($0) }

            // 从 edition key 获取简介
            var description: String?
            let editionKey = firstDoc["cover_edition_key"] as? String
            let workKey = firstDoc["key"] as? String
            AppLogger.warning("OL title search: editionKey=\(editionKey ?? "nil"), workKey=\(workKey ?? "nil")", category: "ISBNLookup")

            if let editionKey {
                description = await fetchOpenLibraryDescription(bookKey: "/books/\(editionKey)")
            }
            if description == nil, let workKey {
                description = await fetchOpenLibraryDescription(bookKey: workKey)
            }

            // 获取作者简介
            var authorDescription: String?
            if let authorKeys = firstDoc["author_key"] as? [String], let firstKey = authorKeys.first {
                authorDescription = await fetchOpenLibraryAuthorBio(authorKey: firstKey)
            }
            AppLogger.warning("OL title search: description=\(description != nil), authorDesc=\(authorDescription != nil)", category: "ISBNLookup")

            return ISBNLookupResult(
                title: resultTitle,
                author: authorName,
                publisher: publisher,
                publishDate: publishYear,
                totalPages: pages,
                price: nil,
                bookDescription: description,
                authorDescription: authorDescription,
                coverImageURL: nil,
                isbn: (firstDoc["isbn"] as? [String])?.first ?? ""
            )
        } catch {
            AppLogger.warning("OL title search: network error: \(error)", category: "ISBNLookup")
            return nil
        }
    }

    /// 通过书名搜索 Google Books
    func searchGoogleBooksByTitle(title: String, author: String?) async -> ISBNLookupResult? {
        var query = "intitle:\(title)"
        if let author, !author.isEmpty {
            query += "+inauthor:\(author)"
        }
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "3")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let firstItem = items.first,
              let volumeInfo = firstItem["volumeInfo"] as? [String: Any] else {
            return nil
        }

        let resultTitle = volumeInfo["title"] as? String ?? title
        let authors = volumeInfo["authors"] as? [String] ?? []
        let authorName = authors.joined(separator: ", ")
        let publisher = volumeInfo["publisher"] as? String
        let publishDate = volumeInfo["publishedDate"] as? String
        let pages = volumeInfo["pageCount"] as? Int
        let description = volumeInfo["description"] as? String

        // ISBN
        var isbn = ""
        if let identifiers = volumeInfo["industryIdentifiers"] as? [[String: Any]] {
            isbn = identifiers.first(where: { $0["type"] as? String == "ISBN_13" })?["identifier"] as? String
                ?? identifiers.first(where: { $0["type"] as? String == "ISBN_10" })?["identifier"] as? String
                ?? ""
        }

        return ISBNLookupResult(
            title: resultTitle,
            author: authorName.isEmpty ? "未知作者" : authorName,
            publisher: publisher,
            publishDate: publishDate,
            totalPages: pages,
            price: nil,
            bookDescription: description,
            authorDescription: nil,
            coverImageURL: nil,
            isbn: isbn
        )
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
