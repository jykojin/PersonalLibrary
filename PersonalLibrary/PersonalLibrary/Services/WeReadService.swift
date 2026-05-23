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
    let finished: Int?  // 1 = 已读完
    let format: String?  // epub, txt, pdf
    let type: Int?  // 0=电子书, 2=有声书(推测)
}

/// 阅读进度
struct WeReadBookProgress: Codable {
    let bookId: String
    let progress: Int?  // 0-100 百分比
    let chapterUid: Int?
    let chapterIdx: Int?
    let readingTime: Int?  // 秒
    let updateTime: Int?  // Unix 时间戳
    let ttsTime: Int?  // 有声书收听时间（秒）
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
    var isSelected: Bool = true
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
        let encoded = bookId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bookId
        let url = URL(string: "\(baseURL)/web/book/info?bookId=\(encoded)")!
        let data = try await makeRequest(url: url)
        return try JSONDecoder().decode(WeReadShelfBook.self, from: data)
    }

    /// 刷新 Cookie
    func renewCookie() async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(baseURL)/web/login/renewal")!)
        request.httpMethod = "POST"
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let body = ["rq": "%2Fweb%2Fshelf%2Fsync"]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 200 {
            // 检查响应体
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errCode = json["errCode"] as? Int {
                return errCode == 0
            }
            return true
        }
        return false
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

            // 判断书籍类型：有 ttsTime > 0 或 type==2 为有声书，其余为电子书
            // 微信读书导入的书不会是纸质书
            let bookType: BookType
            if book.type == 2 || ttsTime > readingTime {
                bookType = .audiobook
            } else {
                bookType = .ebook
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
                progress: progress?.progress ?? 0,
                readingTime: readingTime,
                ttsTime: ttsTime,
                isFinished: book.finished == 1,
                bookType: bookType
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

        // 获取或创建"微信读书"标签（MainActor 操作）
        let wereadTag = try await MainActor.run {
            try findOrCreateTag(name: "微信读书", modelContext: modelContext)
        }

        for item in items where item.isSelected {
            // 检查是否已存在（通过书名+作者去重）— MainActor 操作
            let exists = try await MainActor.run {
                let title = item.title
                let author = item.author
                var descriptor = FetchDescriptor<Book>(
                    predicate: #Predicate { $0.title == title && $0.author == author }
                )
                descriptor.fetchLimit = 1
                return try !modelContext.fetch(descriptor).isEmpty
            }

            if exists {
                skipped += 1
                continue
            }

            // 下载封面（网络操作，在 actor 上执行）
            var coverData: Data?
            if let coverURL = item.cover {
                coverData = await downloadImage(from: coverURL)
            }

            // 创建新书并插入 — MainActor 操作
            try await MainActor.run {
                // 微信读书导入的书类型为电子书或有声书，绝不是纸质书
                let book = Book(
                    title: item.title,
                    author: item.author,
                    translator: item.translator,
                    isbn: item.isbn,
                    publisher: item.publisher,
                    bookType: item.bookType,  // .ebook 或 .audiobook
                    bookDescription: item.intro,
                    coverImageURL: item.cover
                )
                book.wereadBookId = item.id  // 保存微信读书 ID 供后续同步匹配

                // 设置阅读状态
                if item.isFinished {
                    book.status = .finished
                    book.finishedDate = Date()
                } else if item.progress > 0 || item.readingTime > 0 || item.ttsTime > 0 {
                    book.status = .reading
                } else {
                    book.status = .wishlist
                }
                book.statusChangedDate = Date()

                // 封面数据
                book.coverImageData = coverData

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

            // 控制请求频率（封面下载之间）
            try await Task.sleep(for: .milliseconds(50))
        }

        try await MainActor.run {
            try modelContext.save()
        }
        return ImportSummary(imported: imported, skipped: skipped)
    }

    struct ImportSummary {
        let imported: Int
        let skipped: Int
    }

    // MARK: - Private Helpers

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
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10  // 10 秒超时
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// 查找或创建标签（在 MainActor 上下文中调用）
    nonisolated private func findOrCreateTag(name: String, modelContext: ModelContext) throws -> Tag {
        let tagName = name
        var descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.name == tagName }
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let tag = Tag(name: name)
        modelContext.insert(tag)
        return tag
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
