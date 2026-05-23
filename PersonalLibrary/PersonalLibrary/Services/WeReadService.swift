import Foundation
import SwiftData

// MARK: - WeRead API 数据模型

/// 微信读书书架同步响应
struct WeReadShelfResponse: Codable {
    let books: [WeReadShelfBook]?
    let bookProgress: [WeReadBookProgress]?
    let synckey: Int?
    let removed: [String]?
}

/// 书架中的书籍
struct WeReadShelfBook: Codable {
    let bookId: String
    let title: String?
    let author: String?
    let cover: String?
    let translator: String?
    let category: String?
    let publisher: String?
    let publishTime: String?
    let intro: String?
    let isbn: String?
    let price: Double?
    let finished: Int?  // 1 = 已读完（不可靠，需配合 progress 判断）
    let format: String?  // epub, txt, pdf
    let type: Int?  // 0=电子书, 2=有声书(推测)
    let readUpdateTime: Int?  // 加入书架时间（Unix 时间戳）
    let finishReadingTime: Int?  // 读完时间（Unix 时间戳）
}

/// 划线/高亮列表响应
struct WeReadBookmarkListResponse: Codable {
    let updated: [WeReadBookmark]?
}

/// 单条划线
struct WeReadBookmark: Codable {
    let bookmarkId: String?
    let markText: String?
    let chapterName: String?
    let createTime: Int?  // Unix 时间戳
}

/// 阅读进度
struct WeReadBookProgress: Codable {
    let bookId: String
    let progress: Int?  // 0-100 百分比
    let chapterUid: Int?
    let chapterIdx: Int?
    let readingTime: Int?  // 秒
    let updateTime: Int?  // Unix 时间戳（最后阅读时间）
    let ttsTime: Int?  // 有声书收听时间（秒）
    let finishedDate: Int?  // 读完时间（Unix 时间戳）
}

/// 用于 UI 展示的导入条目
struct WeReadImportItem: Identifiable {
    let id: String  // bookId
    let title: String
    let author: String
    let cover: String?
    let publisher: String?
    let isbn: String?
    let intro: String?
    let translator: String?
    let category: String?
    let progress: Int  // 0-100
    let readingTime: Int  // 秒
    let ttsTime: Int  // 有声书时长（秒）
    let isFinished: Bool
    let bookType: BookType  // 电子书或有声书（微信读书不会有纸质书）
    let addedTime: Date?  // 加入书架时间
    let finishedTime: Date?  // 读完时间
    var isSelected: Bool = true

    /// 便捷初始化（addedTime/finishedTime 默认为 nil）
    init(id: String, title: String, author: String, cover: String? = nil,
         publisher: String? = nil, isbn: String? = nil, intro: String? = nil,
         translator: String? = nil, category: String? = nil,
         progress: Int = 0, readingTime: Int = 0, ttsTime: Int = 0,
         isFinished: Bool = false, bookType: BookType = .ebook,
         addedTime: Date? = nil, finishedTime: Date? = nil,
         isSelected: Bool = true) {
        self.id = id
        self.title = title
        self.author = author
        self.cover = cover
        self.publisher = publisher
        self.isbn = isbn
        self.intro = intro
        self.translator = translator
        self.category = category
        self.progress = progress
        self.readingTime = readingTime
        self.ttsTime = ttsTime
        self.isFinished = isFinished
        self.bookType = bookType
        self.addedTime = addedTime
        self.finishedTime = finishedTime
        self.isSelected = isSelected
    }
}

// MARK: - WeRead API Service

/// 微信读书 API 服务
actor WeReadService {

    private let baseURL = "https://weread.qq.com"
    private var cookies: String = ""

    // MARK: - Cookie 管理（使用 Keychain 安全存储）

    /// 设置登录后的 Cookie（保存到 Keychain）
    func setCookies(_ cookieString: String) {
        self.cookies = cookieString
        KeychainService.save(key: KeychainService.wereadCookieKey, string: cookieString)
    }

    /// 获取当前 Cookie（优先内存，fallback Keychain）
    func getCookies() -> String {
        if cookies.isEmpty {
            cookies = KeychainService.loadString(key: KeychainService.wereadCookieKey) ?? ""
        }
        return cookies
    }

    /// 检查是否已登录
    func isLoggedIn() -> Bool {
        let currentCookies = getCookies()
        return currentCookies.contains("wr_skey")
    }

    /// 清除登录状态
    func logout() {
        cookies = ""
        KeychainService.delete(key: KeychainService.wereadCookieKey)
    }

    // MARK: - API 调用

    /// 获取书架数据
    func fetchShelf() async throws -> WeReadShelfResponse {
        let url = URL(string: "\(baseURL)/web/shelf/sync")!
        let data = try await makeRequest(url: url)
        return try JSONDecoder().decode(WeReadShelfResponse.self, from: data)
    }

    /// 获取书籍详情
    func fetchBookInfo(bookId: String) async throws -> WeReadShelfBook {
        let safeId = try validateBookId(bookId)
        let url = URL(string: "\(baseURL)/web/book/info?bookId=\(safeId)")!
        let data = try await makeRequest(url: url)
        return try JSONDecoder().decode(WeReadShelfBook.self, from: data)
    }

    /// 获取书籍划线/高亮列表
    func fetchBookmarks(bookId: String) async throws -> [WeReadBookmark] {
        let safeId = try validateBookId(bookId)
        let url = URL(string: "\(baseURL)/web/book/bookmarklist?bookId=\(safeId)")!
        let data = try await makeRequest(url: url)
        let response = try JSONDecoder().decode(WeReadBookmarkListResponse.self, from: data)
        return response.updated ?? []
    }

    /// 刷新 Cookie
    func renewCookie() async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(baseURL)/web/login/renewal")!)
        request.httpMethod = "POST"
        request.setValue(getCookies(), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let body = ["rq": "%2Fweb%2Fshelf%2Fsync"]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 200 {
            // 关键：从响应头获取新 Cookie 并更新存储
            updateCookiesFromResponse(httpResponse)

            // 检查响应体
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errCode = json["errCode"] as? Int {
                return errCode == 0
            }
            return true
        }
        return false
    }

    /// 从 HTTP 响应头的 Set-Cookie 更新本地存储的 Cookie
    private func updateCookiesFromResponse(_ response: HTTPURLResponse) {
        guard let headerFields = response.allHeaderFields as? [String: String],
              let url = response.url else { return }

        let newCookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        guard !newCookies.isEmpty else { return }

        // 解析当前已有的 cookie 为字典
        var cookieDict: [String: String] = [:]
        let currentCookies = getCookies()
        for pair in currentCookies.split(separator: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            if let eqIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[trimmed.startIndex..<eqIndex])
                let value = String(trimmed[trimmed.index(after: eqIndex)...])
                cookieDict[key] = value
            }
        }

        // 用响应中的新 cookie 覆盖旧值
        for cookie in newCookies {
            cookieDict[cookie.name] = cookie.value
        }

        // 重新组合为 cookie 字符串并保存
        let updatedString = cookieDict.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        self.cookies = updatedString
        KeychainService.save(key: KeychainService.wereadCookieKey, string: updatedString)
    }

    // MARK: - 导入逻辑

    /// 获取所有可导入的书籍（合并书架和进度信息）
    func fetchAllBooks() async throws -> [WeReadImportItem] {
        let shelfData = try await fetchShelf()

        guard let books = shelfData.books else {
            return []
        }

        // 构建进度映射
        var progressMap: [String: WeReadBookProgress] = [:]
        if let progressList = shelfData.bookProgress {
            for p in progressList {
                progressMap[p.bookId] = p
            }
        }

        // 转换为导入条目
        var items: [WeReadImportItem] = []
        for book in books {
            let progress = progressMap[book.bookId]
            let ttsTime = progress?.ttsTime ?? 0
            let readingTime = progress?.readingTime ?? 0
            let progressPercent = progress?.progress ?? 0

            // 判断书籍类型：type==2/3 或有 ttsTime 为有声书，其余为电子书
            // 微信读书导入的书不会是纸质书
            let bookType: BookType
            if book.type == 2 || book.type == 3 || ttsTime > 0 {
                bookType = .audiobook
            } else {
                bookType = .ebook
            }

            // 判断是否读完：progress == 100 或 finished == 1 且有 finishReadingTime
            // 仅 finished==1 不可靠（书架 API 可能对所有书返回 1）
            let isFinished = progressPercent >= 100
                || (book.finished == 1 && (book.finishReadingTime != nil || progress?.finishedDate != nil))

            // 加入书架时间
            let addedTime: Date?
            if let ts = book.readUpdateTime, ts > 0 {
                addedTime = Date(timeIntervalSince1970: TimeInterval(ts))
            } else {
                addedTime = nil
            }

            // 读完时间：优先 book.finishReadingTime，其次 progress.finishedDate，最后 progress.updateTime（仅当已读完时）
            let finishedTime: Date?
            if isFinished {
                if let ts = book.finishReadingTime, ts > 0 {
                    finishedTime = Date(timeIntervalSince1970: TimeInterval(ts))
                } else if let ts = progress?.finishedDate, ts > 0 {
                    finishedTime = Date(timeIntervalSince1970: TimeInterval(ts))
                } else if let ts = progress?.updateTime, ts > 0 {
                    finishedTime = Date(timeIntervalSince1970: TimeInterval(ts))
                } else {
                    finishedTime = nil
                }
            } else {
                finishedTime = nil
            }

            let item = WeReadImportItem(
                id: book.bookId,
                title: book.title ?? "未知书名",
                author: book.author ?? "未知作者",
                cover: book.cover,
                publisher: book.publisher,
                isbn: book.isbn,
                intro: book.intro,
                translator: book.translator,
                category: book.category,
                progress: progressPercent,
                readingTime: readingTime,
                ttsTime: ttsTime,
                isFinished: isFinished,
                bookType: bookType,
                addedTime: addedTime,
                finishedTime: finishedTime
            )
            items.append(item)
        }

        return items
    }

    /// 将选中的微信读书书籍导入到本地数据库
    /// 注意：ModelContext 必须在 MainActor 上操作，此方法内部通过 MainActor.run 确保安全
    func importBooks(_ items: [WeReadImportItem], modelContext: ModelContext) async throws -> ImportSummary {
        var imported = 0
        var skipped = 0

        // 获取或创建"微信读书"标签和书架（MainActor 操作）
        let (wereadTag, wereadShelf) = try await MainActor.run {
            let tag = try findOrCreateTag(name: "微信读书", modelContext: modelContext)
            let shelf = try findOrCreateBookshelf(name: "微信读书", icon: "iphone", modelContext: modelContext)
            return (tag, shelf)
        }

        // 先插入所有书籍（不下载封面），速度优先
        for item in items where item.isSelected {
            // 检查是否已存在（只匹配电子书/有声书，不与纸质书混淆）
            let exists = try await MainActor.run {
                let title = item.title
                let author = item.author
                var descriptor = FetchDescriptor<Book>(
                    predicate: #Predicate { $0.title == title && $0.author == author }
                )
                let matches = try modelContext.fetch(descriptor)
                // 只有已存在同类型（电子书/有声书）才算重复
                return matches.contains(where: { $0.bookType == .ebook || $0.bookType == .audiobook })
            }

            if exists {
                skipped += 1
                continue
            }

            // 创建新书并插入（不等封面下载）
            try await MainActor.run {
                let book = Book(
                    title: item.title,
                    author: item.author,
                    translator: item.translator,
                    isbn: item.isbn,
                    publisher: item.publisher,
                    bookType: item.bookType,
                    bookDescription: item.intro,
                    coverImageURL: item.cover
                )
                book.wereadBookId = item.id
                book.addSource = .wereadImported

                // 加入时间：优先微信读书的加入书架时间
                if let addedTime = item.addedTime {
                    book.addedDate = addedTime
                }

                // 阅读状态：已读完→已读，有阅读时间/进度→正在读，其余→闲置
                if item.isFinished {
                    book.status = .finished
                    book.finishedDate = item.finishedTime ?? Date()
                } else if item.progress > 0 || item.readingTime > 0 || item.ttsTime > 0 {
                    book.status = .reading
                } else {
                    book.status = .idle
                }
                book.statusChangedDate = Date()

                // 书架
                book.bookshelf = wereadShelf

                // 标签
                var bookTags: [Tag] = [wereadTag]
                if let category = item.category, !category.isEmpty {
                    let categoryTag = try findOrCreateTag(name: category, modelContext: modelContext)
                    bookTags.append(categoryTag)
                }
                book.tags = bookTags

                modelContext.insert(book)
            }

            imported += 1
        }

        // 记录导入历史
        let totalSelected = items.filter { $0.isSelected }.count
        try await MainActor.run {
            let record = ImportRecord(
                source: "微信读书导入",
                totalCount: totalSelected,
                successCount: imported,
                skippedCount: skipped
            )
            modelContext.insert(record)
            try modelContext.save()
        }

        // 后台下载封面（不阻塞导入结果返回）
        let booksToFetchCovers = items.filter { $0.isSelected && $0.cover != nil }
        let container = modelContext.container
        Task {
            for item in booksToFetchCovers {
                guard let coverURL = item.cover else { continue }
                let coverData = await downloadImage(from: coverURL)
                if let coverData {
                    await MainActor.run {
                        let bgContext = ModelContext(container)
                        let title = item.title
                        let author = item.author
                        var descriptor = FetchDescriptor<Book>(
                            predicate: #Predicate { $0.title == title && $0.author == author }
                        )
                        descriptor.fetchLimit = 1
                        if let book = try? bgContext.fetch(descriptor).first {
                            book.coverImageData = coverData
                            try? bgContext.save()
                        }
                    }
                }
            }
        }

        return ImportSummary(imported: imported, skipped: skipped)
    }

    /// 查找或创建书架（委托给 BookService）
    nonisolated private func findOrCreateBookshelf(name: String, icon: String, modelContext: ModelContext) throws -> Bookshelf {
        try BookService.findOrCreateBookshelf(name: name, icon: icon, modelContext: modelContext)
    }

    struct ImportSummary {
        let imported: Int
        let skipped: Int
    }

    // MARK: - Private Helpers

    /// 验证 bookId 格式（防止路径注入）
    private func validateBookId(_ bookId: String) throws -> String {
        // WeRead bookId 格式：字母数字、下划线、连字符（通常为纯数字或 hex）
        guard !bookId.isEmpty,
              bookId.count <= 64,
              bookId.range(of: "^[a-zA-Z0-9_\\-]+$", options: .regularExpression) != nil else {
            throw WeReadError.apiError(code: -1, message: "无效的书籍ID")
        }
        return bookId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bookId
    }

    private var userAgent: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }

    private func makeRequest(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15  // 15秒超时，避免长时间等待
        request.setValue(getCookies(), forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://weread.qq.com", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeReadError.networkError
        }

        // 从响应头更新 Cookie（服务器可能在任意请求中轮换）
        updateCookiesFromResponse(httpResponse)

        // 检查 API 错误码
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errCode = json["errCode"] as? Int, errCode != 0 {
            if errCode == -2012 {
                throw WeReadError.cookieExpired
            } else if errCode == -2013 {
                throw WeReadError.authFailed
            } else {
                let errMsg = json["errMsg"] as? String ?? "未知错误"
                throw WeReadError.apiError(code: errCode, message: errMsg)
            }
        }

        guard httpResponse.statusCode == 200 else {
            throw WeReadError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
    }

    private func downloadImage(from urlString: String) async -> Data? {
        await BookService.downloadImage(from: urlString)
    }

    /// 查找或创建标签（委托给 BookService）
    nonisolated private func findOrCreateTag(name: String, modelContext: ModelContext) throws -> Tag {
        try BookService.findOrCreateTag(name: name, modelContext: modelContext)
    }
}

// MARK: - Errors

enum WeReadError: Error, LocalizedError {
    case networkError
    case cookieExpired
    case authFailed
    case httpError(statusCode: Int)
    case apiError(code: Int, message: String)
    case noData

    var errorDescription: String? {
        switch self {
        case .networkError: return "网络连接失败"
        case .cookieExpired: return "登录已过期，请重新扫码登录"
        case .authFailed: return "认证失败，请重新登录"
        case .httpError(let code): return "HTTP 错误 (\(code))"
        case .apiError(_, let message): return "API 错误: \(message)"
        case .noData: return "没有获取到数据"
        }
    }
}
