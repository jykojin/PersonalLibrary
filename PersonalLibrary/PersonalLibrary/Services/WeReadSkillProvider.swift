import Foundation

/// 微信读书 Skill API 模式
/// 通过 Agent Gateway (https://i.weread.qq.com/api/agent/gateway) 访问
/// 认证: Bearer $WEREAD_API_KEY
actor WeReadSkillProvider: WeReadDataSource {

    private let gatewayURL = URL(string: "https://i.weread.qq.com/api/agent/gateway")!
    private let skillVersion = "1.0.3"

    // MARK: - API Key 管理

    private var apiKey: String = ""

    /// 设置 API Key（保存到 Keychain）
    func setApiKey(_ key: String) {
        let sanitized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = sanitized
        KeychainService.save(key: KeychainService.wereadApiKey, string: sanitized)
    }

    /// 获取当前 API Key
    func getApiKey() -> String {
        if apiKey.isEmpty {
            apiKey = KeychainService.loadString(key: KeychainService.wereadApiKey) ?? ""
        }
        return apiKey
    }

    // MARK: - WeReadDataSource Protocol

    func isConnected() -> Bool {
        let key = getApiKey()
        return !key.isEmpty && key.hasPrefix("wrk-")
    }

    func disconnect() {
        apiKey = ""
        KeychainService.delete(key: KeychainService.wereadApiKey)
    }

    func fetchAllBooks() async throws -> [WeReadImportItem] {
        // 1. 获取书架
        let shelfData = try await callAPI(apiName: "/shelf/sync")

        guard let booksArray = shelfData["books"] as? [[String: Any]] else {
            return []
        }

        // 2. 构建进度映射（bookProgress 包含 readingTime、ttsTime、progress、finishedDate）
        var progressMap: [String: [String: Any]] = [:]
        if let progressArray = shelfData["bookProgress"] as? [[String: Any]] {
            for p in progressArray {
                if let bid = p["bookId"] as? String {
                    progressMap[bid] = p
                }
            }
        }

        // 3. 转换为 WeReadImportItem
        var items: [WeReadImportItem] = []

        for bookDict in booksArray {
            guard let bookId = bookDict["bookId"] as? String else { continue }

            let title = bookDict["title"] as? String ?? "未知书名"
            let author = bookDict["author"] as? String ?? "未知作者"
            let cover = bookDict["cover"] as? String
            let publisher = bookDict["publisher"] as? String
            let isbn = bookDict["isbn"] as? String
            let intro = bookDict["intro"] as? String
            let translator = bookDict["translator"] as? String
            let category = bookDict["category"] as? String
            let finishReading = bookDict["finishReading"] as? Int ?? 0
            let readUpdateTime = bookDict["readUpdateTime"] as? Int
            let price = bookDict["price"] as? Double
            let publishTime = bookDict["publishTime"] as? String
            let finishReadingTime = bookDict["finishReadingTime"] as? Int

            // 进度数据
            let progress = progressMap[bookId]
            let readingTime = progress?["readingTime"] as? Int ?? 0
            let ttsTime = progress?["ttsTime"] as? Int ?? 0
            let progressPercent = progress?["progress"] as? Int ?? 0

            let isFinished = progressPercent >= 100
                || (finishReading == 1 && (finishReadingTime != nil || progress?["finishedDate"] != nil))

            let addedTime: Date?
            if let ts = readUpdateTime, ts > 0 {
                addedTime = Date(timeIntervalSince1970: TimeInterval(ts))
            } else {
                addedTime = nil
            }

            // 读完时间
            let finishedTime: Date?
            if isFinished {
                if let ts = finishReadingTime, ts > 0 {
                    finishedTime = Date(timeIntervalSince1970: TimeInterval(ts))
                } else if let ts = progress?["finishedDate"] as? Int, ts > 0 {
                    finishedTime = Date(timeIntervalSince1970: TimeInterval(ts))
                } else if let ts = progress?["updateTime"] as? Int, ts > 0 {
                    finishedTime = Date(timeIntervalSince1970: TimeInterval(ts))
                } else {
                    finishedTime = nil
                }
            } else {
                finishedTime = nil
            }

            let typeInt = bookDict["type"] as? Int ?? 0
            let bookType: BookType = (typeInt == 2 || typeInt == 3) ? .audiobook : .ebook
            let isUserImported = typeInt == 1 || bookId.hasPrefix("CB_")

            let item = WeReadImportItem(
                id: bookId,
                title: title,
                author: author,
                cover: cover,
                publisher: publisher,
                isbn: isbn,
                intro: intro,
                translator: translator,
                category: category,
                progress: progressPercent,
                readingTime: readingTime,
                ttsTime: ttsTime,
                isFinished: isFinished,
                bookType: bookType,
                isUserImported: isUserImported,
                addedTime: addedTime,
                finishedTime: finishedTime,
                price: price,
                publishTime: publishTime
            )
            items.append(item)
        }

        // 3. 处理有声书 (albums)
        if let albumsArray = shelfData["albums"] as? [[String: Any]] {
            for albumDict in albumsArray {
                guard let albumInfo = albumDict["albumInfo"] as? [String: Any],
                      let albumId = albumInfo["albumId"] as? String else { continue }

                let name = albumInfo["name"] as? String ?? "未知专辑"
                let authorName = albumInfo["authorName"] as? String ?? "未知"
                let cover = albumInfo["cover"] as? String
                let intro = albumInfo["intro"] as? String

                let item = WeReadImportItem(
                    id: albumId,
                    title: name,
                    author: authorName,
                    cover: cover,
                    intro: intro,
                    progress: 0,
                    readingTime: 0,
                    ttsTime: 0,
                    isFinished: false,
                    bookType: .audiobook,
                    addedTime: nil,
                    finishedTime: nil
                )
                items.append(item)
            }
        }

        // 4. 精确进度/时长/完成日期 由 enrichBook (sync step 9b) 逐本补全
        //    fetchAllBooks 只需快速返回书架列表

        return items
    }

    func enrichBook(bookId: String) async throws -> WeReadEnrichResult {
        var result = WeReadEnrichResult()

        // CB_ 前缀是用户导入书的固定标识，最可靠
        if bookId.hasPrefix("CB_") {
            result.isUserImported = true
        }

        // 1. 获取书籍详情
        do {
            let info = try await fetchBookInfo(bookId: bookId)
            result.title = info.title
            result.author = info.author
            result.cover = info.cover
            result.translator = info.translator
            result.category = info.category
            result.publisher = info.publisher
            result.isbn = info.isbn
            result.intro = info.intro
            result.price = info.price
            result.publishTime = info.publishTime
            if let type = info.type {
                if type == 2 || type == 3 {
                    result.bookType = .audiobook
                }
                if type == 1 {
                    result.isUserImported = true
                }
            }
        } catch {
            AppLogger.warning("Skill enrichBook[\(bookId)] fetchBookInfo failed: \(error)", category: "WeRead")
        }

        // 2. 获取阅读进度（含时长 + 开始阅读时间 + 完成时间）
        do {
            let progressData = try await callAPI(apiName: "/book/getprogress", params: ["bookId": bookId])
            if let book = progressData["book"] as? [String: Any] {
                // readingTime / recordReadingTime：累积阅读秒数（尝试两种字段名）
                let readingTime = book["readingTime"] as? Int
                    ?? book["recordReadingTime"] as? Int ?? 0
                // ttsTime：听书/TTS时长（秒）
                let ttsTime = book["ttsTime"] as? Int ?? 0
                let totalSeconds = readingTime + ttsTime
                if totalSeconds > 0 {
                    result.readingHours = Double(totalSeconds) / 3600.0
                }
                // progress: 阅读进度百分比
                if let prog = book["progress"] as? Int {
                    result.progress = prog
                }
                // startReadingTime: 开始阅读时间（也作为加入书架时间）
                if let startTime = book["startReadingTime"] as? Int, startTime > 0 {
                    result.startedReadingTime = Date(timeIntervalSince1970: TimeInterval(startTime))
                    result.addedTime = Date(timeIntervalSince1970: TimeInterval(startTime))
                    result.isStartedReadingTimeEstimated = false
                } else if totalSeconds > 0, let updateTime = book["updateTime"] as? Int, updateTime > 0 {
                    // 回退策略：API 未返回 startReadingTime 但有阅读记录时，
                    // 用 updateTime - totalSeconds 估算首次阅读时间
                    let estimatedStart = max(0, updateTime - totalSeconds)
                    result.startedReadingTime = Date(timeIntervalSince1970: TimeInterval(estimatedStart))
                    result.addedTime = Date(timeIntervalSince1970: TimeInterval(estimatedStart))
                    result.isStartedReadingTimeEstimated = true
                }
                // finishTime 仅 progress=100 时存在
                if let finishTime = book["finishTime"] as? Int, finishTime > 0 {
                    result.finishedTime = Date(timeIntervalSince1970: TimeInterval(finishTime))
                }
            }
        } catch {
            AppLogger.warning("Skill enrichBook[\(bookId)] getprogress failed: \(error)", category: "WeRead")
        }
        return result
    }

    func fetchBookmarks(bookId: String) async throws -> [WeReadBookmark] {
        let data = try await callAPI(apiName: "/book/bookmarklist", params: ["bookId": bookId])

        guard let updated = data["updated"] as? [[String: Any]] else {
            return []
        }

        return updated.compactMap { dict in
            WeReadBookmark(
                bookmarkId: dict["bookmarkId"] as? String,
                markText: dict["markText"] as? String,
                chapterName: nil,
                createTime: dict["createTime"] as? Int
            )
        }
    }

    func fetchBookInfo(bookId: String) async throws -> WeReadShelfBook {
        let data = try await callAPI(apiName: "/book/info", params: ["bookId": bookId])

        return WeReadShelfBook(
            bookId: data["bookId"] as? String ?? bookId,
            title: data["title"] as? String,
            author: data["author"] as? String,
            cover: data["cover"] as? String,
            translator: data["translator"] as? String,
            category: data["category"] as? String,
            publisher: data["publisher"] as? String,
            publishTime: data["publishTime"] as? String,
            intro: data["intro"] as? String,
            isbn: data["isbn"] as? String,
            price: data["price"] as? Double,
            finished: nil,
            format: nil,
            type: data["type"] as? Int,
            readUpdateTime: nil,
            finishReadingTime: nil
        )
    }

    // MARK: - Skill-Only Extra APIs

    /// 搜索书城
    func searchBooks(keyword: String, count: Int = 10) async throws -> [[String: Any]] {
        let data = try await callAPI(apiName: "/store/search", params: [
            "keyword": keyword,
            "scope": 10,
            "count": count
        ])
        guard let results = data["results"] as? [[String: Any]],
              let first = results.first,
              let books = first["books"] as? [[String: Any]] else {
            return []
        }
        return books
    }

    /// 获取个性化推荐
    func getRecommendations(count: Int = 12) async throws -> [[String: Any]] {
        let data = try await callAPI(apiName: "/book/recommend", params: ["count": count])
        return data["books"] as? [[String: Any]] ?? []
    }

    /// 获取阅读统计
    func getReadingStats(mode: String = "monthly") async throws -> [String: Any] {
        return try await callAPI(apiName: "/readdata/detail", params: ["mode": mode])
    }

    /// 获取笔记本概览
    func getNotebooks(count: Int = 100) async throws -> [String: Any] {
        return try await callAPI(apiName: "/user/notebooks", params: ["count": count])
    }

    /// 验证 API Key 是否有效（调用书架接口测试）
    func validateApiKey() async throws -> Bool {
        do {
            _ = try await callAPI(apiName: "/shelf/sync")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Network

    private func callAPI(apiName: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        let key = getApiKey()
        guard !key.isEmpty else {
            throw WeReadError.authFailed
        }

        var body: [String: Any] = [
            "api_name": apiName,
            "skill_version": skillVersion
        ]
        for (k, v) in params {
            body[k] = v
        }

        var request = URLRequest(url: gatewayURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeReadError.networkError
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw WeReadError.authFailed
        default:
            throw WeReadError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WeReadError.noData
        }

        if let errcode = json["errcode"] as? Int, errcode != 0 {
            let message = json["errmsg"] as? String ?? "未知错误"
            throw WeReadError.apiError(code: errcode, message: message)
        }

        return json
    }
}
