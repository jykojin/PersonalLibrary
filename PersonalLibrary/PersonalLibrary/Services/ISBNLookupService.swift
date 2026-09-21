import Foundation

// MARK: - 豆瓣请求限速器

/// 豆瓣请求限速器（全局共享）— 保证所有豆瓣请求间隔至少 5 秒
/// 防止并发批量补全时被豆瓣封 IP
actor DoubanRateLimiter {
    static let shared = DoubanRateLimiter()
    private var lastRequestTime: Date = .distantPast
    private let minInterval: TimeInterval = 5.0
    /// 单次 wait 等待上限 — 防止批量任务结束/取消后 reservation 残留导致后续请求长时间卡住
    /// 30 秒覆盖正常并发场景（3 路 × 5s = 15s），又能在状态污染时快速恢复
    private let maxWait: TimeInterval = 30.0

    func wait() async {
        let now = Date()
        var nextAllowed = max(now, lastRequestTime.addingTimeInterval(minInterval))
        if nextAllowed.timeIntervalSince(now) > maxWait {
            // reservation 队列过长（>30s），多半是前面被排队的 task 已退出未释放
            // 重置到"now + minInterval"，避免新调用方被卡住
            nextAllowed = now.addingTimeInterval(minInterval)
        }
        lastRequestTime = nextAllowed     // reserve synchronously, before any await
        let delay = nextAllowed.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
    }
}

// MARK: - 智能补全数据源状态

/// 单个数据源的查询状态
enum LookupSourceStatus: Equatable, Sendable {
    case notAttempted       // 未尝试（如没有ISBN则跳过ISBN类查询）
    case found             // 找到数据
    case notFound          // 查询成功但没有数据
    case retryableFailure(String)
    case fatalFailure(String)
    case validationRejected(String)
    case cancelled
    case error(String)     // 查询出错

    var displayText: String {
        switch self {
        case .notAttempted: return "未尝试"
        case .found: return "已找到"
        case .notFound: return "未找到"
        case .retryableFailure(let msg): return "稍后可重试: \(msg)"
        case .fatalFailure(let msg): return "失败: \(msg)"
        case .validationRejected(let msg): return "验证拒绝: \(msg)"
        case .cancelled: return "已取消"
        case .error(let msg): return "出错: \(msg)"
        }
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
    var translator: String? = nil
    var coverImageURL: String?
    var isbn: String
    var isbnIsSourceVerified: Bool = false
    var doubanURL: String?
}

/// ISBN 查询服务 — 通过 ISBN 自动获取书籍信息
/// 优先使用 Open Library API（免费、无需 API key）
actor ISBNLookupService {
    private let httpClient: any HTTPDataClient

    init(httpClient: any HTTPDataClient = URLSessionHTTPDataClient()) {
        self.httpClient = httpClient
    }

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
        if let result = try await lookupFromDouban(isbn: cleanISBN),
           isVerifiedISBNResult(result, requestedISBN: cleanISBN) {
            return result
        }

        // 备选：Open Library API
        if let result = try await lookupFromOpenLibrary(isbn: cleanISBN),
           isVerifiedISBNResult(result, requestedISBN: cleanISBN) {
            return result
        }

        // 备选：Google Books API
        if let result = try await lookupFromGoogleBooks(isbn: cleanISBN),
           isVerifiedISBNResult(result, requestedISBN: cleanISBN) {
            return result
        }

        // 备选：Goodreads（英文书覆盖率高）
        if let result = try await lookupFromGoodreads(isbn: cleanISBN),
           isVerifiedISBNResult(result, requestedISBN: cleanISBN) {
            return result
        }

        return nil
    }

    private func isVerifiedISBNResult(
        _ result: ISBNLookupResult,
        requestedISBN: String
    ) -> Bool {
        result.isbnIsSourceVerified
            && BookIdentityMatcher.isbnMatches(requestedISBN, result.isbn)
    }

    // MARK: - 豆瓣 ISBN 查询

    func lookupFromDouban(isbn: String) async throws -> ISBNLookupResult? {
        // 豆瓣 ISBN 跳转：/isbn/{ISBN}/ → 301 到书籍页面
        guard let url = URL(string: "https://book.douban.com/isbn/\(isbn)/") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        // 全局豆瓣限速：保证至少 5 秒间隔，防止并发批量补全被封 IP
        await DoubanRateLimiter.shared.wait()

        // 使用自动跟随重定向的 session
        let (data, response) = try await httpClient.data(for: request)
        guard try validateLookupResponse(response) else { return nil }

        // 防止异常大响应导致内存耗尽
        guard data.count <= 5_000_000 else { throw HTTPDataClientError.responseTooLarge }

        guard let html = String(data: data, encoding: .utf8) else { return nil }

        guard let page = DoubanBookPage.parse(html) else { return nil }

        // 豆瓣链接（最终跳转的 URL）
        let doubanURL = response.url?.absoluteString

        AppLogger.info("Douban found: \(page.title) by \(page.author ?? "未知作者")", category: "ISBNLookup")

        return ISBNLookupResult(
            title: page.title,
            author: page.author ?? "未知作者",
            publisher: page.publisher,
            publishDate: page.publishDate,
            totalPages: page.totalPages,
            price: page.price,
            bookDescription: page.bookDescription,
            authorDescription: page.authorDescription,
            translator: page.translator,
            coverImageURL: page.coverImageURL,
            isbn: page.isbn ?? isbn,
            isbnIsSourceVerified: page.isbn?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
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

    // MARK: - Open Library API

    func lookupFromOpenLibrary(isbn: String) async throws -> ISBNLookupResult? {
        let urlString = "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10  // 10秒超时
        let (data, response) = try await httpClient.data(for: request)
        guard try validateLookupResponse(response) else { return nil }

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

        return ISBNLookupResult(
            title: title,
            author: authorName,
            publisher: publisher,
            publishDate: publishDate,
            totalPages: pages,
            price: nil,
            bookDescription: nil,
            authorDescription: nil,
            coverImageURL: coverURL ?? "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg",
            isbn: isbn,
            isbnIsSourceVerified: true
        )
    }

    // MARK: - Google Books API

    private func lookupFromGoogleBooks(isbn: String) async throws -> ISBNLookupResult? {
        let urlString = "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10  // 10秒超时
        let (data, response) = try await httpClient.data(for: request)
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

        let sourceISBNs = (volumeInfo["industryIdentifiers"] as? [[String: Any]] ?? [])
            .compactMap { ($0["identifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let sourceISBN = sourceISBNs.first(where: {
            BookIdentityMatcher.isbnMatches(isbn, $0)
        }) ?? sourceISBNs.first

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
            isbn: sourceISBN ?? "",
            isbnIsSourceVerified: sourceISBN != nil
        )
    }

    // MARK: - Goodreads

    func lookupFromGoodreads(isbn: String) async throws -> ISBNLookupResult? {
        guard let url = URL(string: "https://www.goodreads.com/book/isbn/\(isbn)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await httpClient.data(for: request)
        guard try validateLookupResponse(response) else { return nil }

        // 防止异常大响应
        guard data.count <= 5_000_000 else { throw HTTPDataClientError.responseTooLarge }

        guard let html = String(data: data, encoding: .utf8) else { return nil }

        // 从 JSON-LD 提取结构化数据
        guard let jsonLD = extractGoodreadsJsonLD(from: html) else { return nil }

        let title = jsonLD["name"] as? String ?? ""
        guard !title.isEmpty else { return nil }

        // 作者
        let author = extractGoodreadsAuthor(from: jsonLD)
        let authorName = author?.name ?? "未知作者"

        // 页数
        let pages = (jsonLD["numberOfPages"] as? Int)
            ?? (jsonLD["numberOfPages"] as? String).flatMap { Int($0) }

        let publication = extractGoodreadsPublicationFields(from: jsonLD)

        // ISBN
        let sourceISBN = (jsonLD["isbn"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookISBN = sourceISBN?.isEmpty == false ? sourceISBN! : isbn

        // 描述
        let description = extractGoodreadsDescription(from: html)

        // 封面
        let coverURL = extractPattern(#"property="og:image"\s+content="([^"]+)""#, from: html)
            ?? extractPattern(#"content="([^"]+)"\s+property="og:image""#, from: html)

        AppLogger.info("Goodreads found: \(title) by \(authorName)", category: "ISBNLookup")

        return ISBNLookupResult(
            title: title,
            author: authorName,
            publisher: publication.publisher,
            publishDate: publication.publishDate,
            totalPages: pages,
            price: publication.price,
            bookDescription: description,
            authorDescription: author?.description,
            coverImageURL: coverURL,
            isbn: bookISBN,
            isbnIsSourceVerified: sourceISBN?.isEmpty == false
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

    private func extractGoodreadsPublicationFields(
        from jsonLD: [String: Any]
    ) -> (publisher: String?, publishDate: String?, price: String?) {
        func nonEmptyString(_ value: Any?) -> String? {
            let text: String?
            if let value = value as? String {
                text = value
            } else if let value = value as? NSNumber {
                text = value.stringValue
            } else {
                text = nil
            }

            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }

        let publisher: String?
        if let publisherObject = jsonLD["publisher"] as? [String: Any] {
            publisher = nonEmptyString(publisherObject["name"])
        } else {
            publisher = nonEmptyString(jsonLD["publisher"])
        }

        let publishDate = nonEmptyString(jsonLD["datePublished"])
        let offer: [String: Any]?
        if let singleOffer = jsonLD["offers"] as? [String: Any] {
            offer = singleOffer
        } else {
            offer = (jsonLD["offers"] as? [[String: Any]])?.first
        }

        let amount = nonEmptyString(offer?["price"])
        let currency = nonEmptyString(offer?["priceCurrency"])
        let price: String? = if let amount, let currency {
            "\(currency.uppercased()) \(amount)"
        } else {
            nil
        }

        return (publisher, publishDate, price)
    }

    private func extractGoodreadsAuthor(
        from jsonLD: [String: Any]
    ) -> (name: String, description: String?)? {
        let authors: [[String: Any]]
        if let values = jsonLD["author"] as? [[String: Any]] {
            authors = values
        } else if let value = jsonLD["author"] as? [String: Any] {
            authors = [value]
        } else {
            return nil
        }

        for author in authors {
            guard let name = author["name"] as? String else { continue }
            let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedName.isEmpty else { continue }
            let description = (author["description"] as? String).flatMap { value -> String? in
                let cleaned = cleanHTMLTags(value)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty,
                      cleaned.count <= AITextBudget.maximumDescriptionCharacters else {
                    return nil
                }
                return cleaned
            }
            return (cleanedName, description)
        }
        return nil
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
    func searchGoodreadsByTitle(title: String, author: String) async throws -> ISBNLookupResult? {
        let query = author.isEmpty || author == "未知作者" ? title : "\(title) \(author)"
        guard var components = URLComponents(string: "https://www.goodreads.com/search") else { return nil }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard data.count <= 5_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        // 从搜索结果页提取第一本书的链接
        let linkPattern = #"/book/show/(\d+)"#
        guard let bookPath = extractPattern(linkPattern, from: html) else { return nil }

        // 访问书籍详情页
        guard let bookURL = URL(string: "https://www.goodreads.com/book/show/\(bookPath)") else { return nil }
        var bookRequest = URLRequest(url: bookURL)
        bookRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        bookRequest.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        bookRequest.timeoutInterval = 15

        let (bookData, bookResp) = try await httpClient.data(for: bookRequest)
        guard let bookHttpResp = bookResp as? HTTPURLResponse,
              bookHttpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard bookData.count <= 5_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        guard let bookHTML = String(data: bookData, encoding: .utf8) else { return nil }

        // 复用现有解析逻辑
        guard let jsonLD = extractGoodreadsJsonLD(from: bookHTML) else { return nil }

        let bookTitle = jsonLD["name"] as? String ?? ""
        guard !bookTitle.isEmpty else { return nil }

        let author = extractGoodreadsAuthor(from: jsonLD)
        let authorName = author?.name ?? "未知作者"

        let pages = (jsonLD["numberOfPages"] as? Int)
            ?? (jsonLD["numberOfPages"] as? String).flatMap { Int($0) }

        let publication = extractGoodreadsPublicationFields(from: jsonLD)

        let description = extractGoodreadsDescription(from: bookHTML)

        AppLogger.info("Goodreads(title search) found: \(bookTitle) by \(authorName)", category: "ISBNLookup")

        return ISBNLookupResult(
            title: bookTitle,
            author: authorName,
            publisher: publication.publisher,
            publishDate: publication.publishDate,
            totalPages: pages,
            price: publication.price,
            bookDescription: description,
            authorDescription: author?.description,
            coverImageURL: nil,
            isbn: jsonLD["isbn"] as? String ?? ""
        )
    }

    // MARK: - 书名搜索（无 ISBN 时使用）

    /// 通过书名搜索 Open Library
    func searchOpenLibraryByTitle(title: String, author: String?) async throws -> ISBNLookupResult? {
        // 先用完整标题搜索，0 结果时用主标题（冒号/破折号前的部分）重试
        if let result = try await searchOpenLibraryByTitleOnce(title: title, author: author) {
            return result
        }
        // 降级：截取主标题重试
        let separators: [Character] = [":", "：", "—", "–", "｜", "|"]
        if let idx = title.firstIndex(where: { separators.contains($0) }) {
            let mainTitle = String(title[..<idx]).trimmingCharacters(in: .whitespaces)
            if !mainTitle.isEmpty && mainTitle != title {
                AppLogger.warning("OL title search: retry with mainTitle=\(mainTitle)", category: "ISBNLookup")
                return try await searchOpenLibraryByTitleOnce(title: mainTitle, author: author)
            }
        }
        return nil
    }

    private func searchOpenLibraryByTitleOnce(title: String, author: String?) async throws -> ISBNLookupResult? {
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

        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        AppLogger.warning("OL title search: HTTP \(httpResponse.statusCode), bytes=\(data.count)", category: "ISBNLookup")
        guard httpResponse.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard data.count <= 5_000_000 else { throw URLError(.dataLengthExceedsMaximum) }

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

        return ISBNLookupResult(
            title: resultTitle,
            author: authorName,
            publisher: publisher,
            publishDate: publishYear,
            totalPages: pages,
            price: nil,
            bookDescription: nil,
            authorDescription: nil,
            coverImageURL: nil,
            isbn: (firstDoc["isbn"] as? [String])?.first ?? ""
        )
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

        guard let (data, response) = try? await httpClient.data(for: request),
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
            let (data, response) = try await httpClient.data(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func validateLookupResponse(_ response: URLResponse) throws -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 404 { return false }
        guard httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return true
    }
}
