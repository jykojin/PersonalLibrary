import SwiftUI
import SwiftData

/// 数据维护视图
/// 四个 Tab：作者、出版社、标签、批量工具
/// 点击条目 → 查看关联图书；左滑 → 修改名称
struct DataMaintenanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.addedDate, order: .reverse) private var allBooks: [Book]
    @Query private var allTags: [Tag]

    @State private var selectedTab = 0  // 0=作者, 1=出版社, 2=标签, 3=批量工具
    @State private var searchText = ""

    // 编辑
    @State private var editingItem: NameCountItem?
    @State private var newName = ""
    @State private var showingResult = false
    @State private var resultMessage = ""

    // 标签新增
    @State private var showingAddTag = false
    @State private var newTagName = ""

    // 工具
    @State private var isCleaning = false
    @State private var showingCleanResult = false
    @State private var cleanResultMessage = ""

    // 批量增补进度
    @State private var batchProgress: Double = 0
    @State private var batchTotal: Int = 0
    @State private var batchCurrent: Int = 0
    @State private var batchStatusText: String = ""
    @State private var isBatchRunning = false
    @State private var batchTask: Task<Void, Never>?
    @State private var activeBatchType: BatchType = .paper
    @State private var batchCancelled = false  // 手动取消标志（跨 Task.detached）
    private enum BatchType { case paper, weread }

    var body: some View {
        VStack(spacing: 0) {
            // Tab 切换
            Picker("类型", selection: $selectedTab) {
                Text("作者").tag(0)
                Text("出版社").tag(1)
                Text("标签").tag(2)
                Text("批量工具").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedTab == 3 {
                batchToolsView
            } else {
                dataListView
            }
        }
        .navigationTitle("数据维护")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingItem) { item in
            editSheet(for: item)
        }
        .alert("完成", isPresented: $showingResult) {
            Button("好的") {}
        } message: {
            Text(resultMessage)
        }
        .alert("完成", isPresented: $showingCleanResult) {
            Button("好的") {}
        } message: {
            Text(cleanResultMessage)
        }
        .alert("新增标签", isPresented: $showingAddTag) {
            TextField("标签名称", text: $newTagName)
            Button("添加") { addTag() }
            Button("取消", role: .cancel) { newTagName = "" }
        }
    }

    // MARK: - 批量工具 Tab

    private var batchToolsView: some View {
        List {
            Section {
                Button {
                    Task { await cleanAuthorNames() }
                } label: {
                    HStack {
                        Label("作者名繁转简", systemImage: "character.textbox")
                        Spacer()
                        if isCleaning {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isCleaning || isBatchRunning)

                Button {
                    Task { await normalizeMultiValues() }
                } label: {
                    HStack {
                        Label("规范分隔符", systemImage: "person.2")
                        Spacer()
                        if isCleaning {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isCleaning || isBatchRunning)
            } header: {
                Text("格式修正")
            } footer: {
                Text("繁转简：「張愛玲」→「张爱玲」\n规范分隔符：统一用英文逗号+空格分隔")
            }

            Section {
                Button {
                    if isBatchRunning && activeBatchType == .paper {
                        batchCancelled = true
                        batchTask?.cancel()
                        batchStatusText = "正在停止…"
                    } else {
                        activeBatchType = .paper
                        batchCancelled = false
                        batchTask = Task { await batchEnrichPaperBooks() }
                    }
                } label: {
                    HStack {
                        let isActive = isBatchRunning && activeBatchType == .paper
                        Label(
                            isActive ? (batchCancelled ? "正在停止…" : "停止补全") : "批量补全纸质书信息",
                            systemImage: isActive ? "stop.circle" : "book.closed"
                        )
                        .foregroundStyle(isActive ? .red : .accentColor)
                        Spacer()
                        if isActive {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isCleaning || (isBatchRunning && activeBatchType != .paper) || batchCancelled)

                Button {
                    if isBatchRunning && activeBatchType == .weread {
                        batchCancelled = true
                        batchTask?.cancel()
                        batchStatusText = "正在停止…"
                    } else {
                        activeBatchType = .weread
                        batchCancelled = false
                        batchTask = Task { await batchEnrichWeReadBooks() }
                    }
                } label: {
                    HStack {
                        let isActive = isBatchRunning && activeBatchType == .weread
                        Label(
                            isActive ? (batchCancelled ? "正在停止…" : "停止补全") : "批量补全微信读书图书信息",
                            systemImage: isActive ? "stop.circle" : "headphones"
                        )
                        .foregroundStyle(isActive ? .red : .accentColor)
                        Spacer()
                        if isActive {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isCleaning || (isBatchRunning && activeBatchType != .weread))
            } header: {
                Text("信息补全")
            } footer: {
                Text("纸质书：从豆瓣 → Open Library → Google Books → Goodreads 查询补全\n微信读书：从微信读书 API 补全出版社、定价、简介、阅读时长、完成日期")
            }

            // 进度区域
            if isBatchRunning {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(batchStatusText)
                            .font(.subheadline)
                        ProgressView(value: batchProgress)
                        Text("\(batchCurrent)/\(batchTotal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 数据列表 View

    private var dataListView: some View {
        VStack(spacing: 0) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 8)

            // 列表
            List {
                // 数据列表
                Section {
                    ForEach(filteredItems) { item in
                        NavigationLink(destination: ItemBooksView(
                            itemName: item.name,
                            fieldType: selectedTab,
                            allBooks: allBooks
                        )) {
                            HStack {
                                Text(item.name)
                                    .font(.body)
                                    .lineLimit(2)
                                Spacer()
                                Text("\(item.count) 本")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("修改") {
                                newName = item.name
                                editingItem = item
                            }
                            .tint(.orange)

                            if selectedTab == 2 {
                                Button("删除", role: .destructive) {
                                    deleteTag(named: item.name)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("\(filteredItems.count) 项")
                        Spacer()
                        if selectedTab == 2 {
                            Button {
                                showingAddTag = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Data

    private var authorItems: [NameCountItem] {
        var dict: [String: Int] = [:]
        for book in allBooks where !book.isArchived {
            let authors = book.author.components(separatedBy: ", ")
            for name in authors {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed != "未知作者" {
                    dict[trimmed, default: 0] += 1
                }
            }
        }
        return dict.map { NameCountItem(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var publisherItems: [NameCountItem] {
        var dict: [String: Int] = [:]
        for book in allBooks where !book.isArchived {
            if let p = book.publisher, !p.isEmpty {
                let publishers = p.components(separatedBy: ", ")
                for name in publishers {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        dict[trimmed, default: 0] += 1
                    }
                }
            }
        }
        return dict.map { NameCountItem(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var tagItems: [NameCountItem] {
        allTags.map { tag in
            let count = (tag.books ?? []).filter { !$0.isArchived }.count
            return NameCountItem(name: tag.name, count: count)
        }
        .sorted { $0.count > $1.count }
    }

    private var currentItems: [NameCountItem] {
        switch selectedTab {
        case 0: return authorItems
        case 1: return publisherItems
        default: return tagItems
        }
    }

    private var filteredItems: [NameCountItem] {
        if searchText.isEmpty { return currentItems }
        return currentItems.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Edit Sheet

    private func editSheet(for item: NameCountItem) -> some View {
        NavigationStack {
            Form {
                Section("当前名称") {
                    Text(item.name)
                        .foregroundStyle(.secondary)
                }

                Section("修改为") {
                    TextField("输入新名称", text: $newName)
                }

                Section("影响范围") {
                    let typeLabel = selectedTab == 0 ? "作者" : (selectedTab == 1 ? "出版社" : "标签")
                    Text("将修改 \(item.count) 本书的\(typeLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("修改名称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { editingItem = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        applyRename()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              newName == item.name)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func applyRename() {
        guard let item = editingItem else { return }
        let oldName = item.name
        let trimmedNew = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmedNew.isEmpty, trimmedNew != oldName else { return }

        let tab = selectedTab
        let container = modelContext.container
        let bookIDs = allBooks.map(\.persistentModelID)
        let tagIDs = allTags.map(\.persistentModelID)

        editingItem = nil

        Task {
            let updatedCount = await Task.detached(priority: .utility) {
                let bgContext = ModelContext(container)
                bgContext.autosaveEnabled = false
                var count = 0

                if tab == 0 {
                    for id in bookIDs {
                        guard let book = bgContext.model(for: id) as? Book else { continue }
                        if book.author == oldName {
                            book.author = trimmedNew
                            count += 1
                        } else if book.author.contains(oldName) {
                            let parts = book.author.components(separatedBy: ", ")
                            let newParts = parts.map { $0 == oldName ? trimmedNew : $0 }
                            let joined = newParts.joined(separator: ", ")
                            if joined != book.author {
                                book.author = joined
                                count += 1
                            }
                        }
                    }
                } else if tab == 1 {
                    for id in bookIDs {
                        guard let book = bgContext.model(for: id) as? Book else { continue }
                        if book.publisher == oldName {
                            book.publisher = trimmedNew
                            count += 1
                        } else if let p = book.publisher, p.contains(oldName) {
                            let parts = p.components(separatedBy: ", ")
                            let newParts = parts.map { $0 == oldName ? trimmedNew : $0 }
                            let joined = newParts.joined(separator: ", ")
                            if joined != p {
                                book.publisher = joined
                                count += 1
                            }
                        }
                    }
                } else {
                    // 标签重命名
                    for id in tagIDs {
                        guard let tag = bgContext.model(for: id) as? Tag else { continue }
                        if tag.name == oldName {
                            tag.name = trimmedNew
                            count = (tag.books ?? []).count
                            break
                        }
                    }
                }

                if count > 0 { try? bgContext.save() }
                return count
            }.value

            resultMessage = "已将「\(oldName)」改为「\(trimmedNew)」，更新了 \(updatedCount) 本书"
            showingResult = true
        }
    }

    private func deleteTag(named name: String) {
        guard let tag = allTags.first(where: { $0.name == name }) else { return }
        modelContext.delete(tag)
        try? modelContext.save()
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !allTags.contains(where: { $0.name == trimmed }) else {
            newTagName = ""
            return
        }
        let tag = Tag(name: trimmed)
        modelContext.insert(tag)
        try? modelContext.save()
        newTagName = ""
    }

    // MARK: - 批量工具

    private func cleanAuthorNames() async {
        isCleaning = true
        defer { isCleaning = false }

        let container = modelContext.container
        let bookIDs = allBooks.map(\.persistentModelID)

        let updatedCount = await Task.detached(priority: .utility) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            var count = 0
            for id in bookIDs {
                guard let book = bgContext.model(for: id) as? Book else { continue }
                let original = book.author
                let mutable = NSMutableString(string: original)
                CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
                let simplified = mutable as String
                if simplified != original {
                    book.author = simplified
                    count += 1
                }
            }
            if count > 0 { try? bgContext.save() }
            return count
        }.value

        cleanResultMessage = updatedCount > 0
            ? "已将 \(updatedCount) 本书的作者名转为简体"
            : "所有作者名已是简体，无需修改"
        showingCleanResult = true
    }

    private func normalizeMultiValues() async {
        isCleaning = true
        defer { isCleaning = false }

        let container = modelContext.container
        let bookIDs = allBooks.map(\.persistentModelID)

        let totalFixes = await Task.detached(priority: .utility) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            let separators = CharacterSet(charactersIn: "；;/，")
            var fixes = 0

            for id in bookIDs {
                guard let book = bgContext.model(for: id) as? Book else { continue }
                let authorNorm = self.normalizeField(book.author, separators: separators)
                if authorNorm != book.author {
                    book.author = authorNorm
                    fixes += 1
                }
                if let t = book.translator, !t.isEmpty {
                    let tNorm = self.normalizeField(t, separators: separators)
                    if tNorm != t {
                        book.translator = tNorm
                        fixes += 1
                    }
                }
                if let p = book.publisher, !p.isEmpty {
                    let pNorm = self.normalizeField(p, separators: separators)
                    if pNorm != p {
                        book.publisher = pNorm
                        fixes += 1
                    }
                }
            }

            if fixes > 0 { try? bgContext.save() }
            return fixes
        }.value

        cleanResultMessage = totalFixes > 0
            ? "已修复 \(totalFixes) 条记录的分隔符格式"
            : "所有数据格式已正确，无需修复"
        showingCleanResult = true
    }

    private func normalizeField(_ value: String, separators: CharacterSet) -> String {
        let parts = value.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parts.count <= 1 { return value.trimmingCharacters(in: .whitespaces) }
        return parts.joined(separator: ", ")
    }

    // MARK: - 批量补全（统一入口）

    private func batchEnrichPaperBooks() async {
        let bookIDs = allBooks.filter {
            !$0.isArchived && $0.bookType == .paper
            && $0.needsEnrichment && $0.lastEnrichmentDate == nil
        }.map(\.persistentModelID)

        await batchEnrich(
            bookIDs: bookIDs,
            label: "paper",
            emptyMessage: "所有纸质书信息已完整，无需补全",
            doneMessage: { s, t in "完成！\(s)/\(t) 本书成功补全信息" }
        )
    }

    private func batchEnrichWeReadBooks() async {
        let books = allBooks.filter {
            !$0.isArchived && $0.wereadBookId != nil && $0.wereadEnrichedDate == nil
        }

        guard !books.isEmpty else {
            cleanResultMessage = "所有微信读书图书信息已完整，无需补全"
            showingCleanResult = true
            return
        }

        isBatchRunning = true
        batchTotal = books.count
        batchCurrent = 0
        batchProgress = 0
        batchStatusText = "正在补全..."

        let provider: any WeReadDataSource = WeReadConnectionMode.current == .skill
            ? WeReadSkillProvider()
            : WeReadService()

        var successCount = 0

        for (index, book) in books.enumerated() {
            if batchCancelled || Task.isCancelled { break }
            guard let bookId = book.wereadBookId else { continue }

            await MainActor.run {
                self.batchCurrent = index + 1
                self.batchProgress = Double(index + 1) / Double(books.count)
                self.batchStatusText = "正在补全（\(book.title)）\(index + 1)/\(books.count)"
            }

            if index > 0 && index % 3 == 0 {
                try? await Task.sleep(for: .seconds(1))
            }

            do {
                let enrichResult = try await provider.enrichBook(bookId: bookId)
                await MainActor.run {
                    enrichResult.applyToBook(book)
                    book.wereadEnrichedDate = Date()
                }
                successCount += 1
            } catch {
                AppLogger.warning("批量补全微信读书失败 (\(book.title)): \(error)", category: "BatchEnrich")
            }

            // 每 10 本保存一次
            if (index + 1) % 10 == 0 {
                try? await MainActor.run { try modelContext.save() }
            }
        }

        try? await MainActor.run { try modelContext.save() }

        let wasCancelled = batchCancelled
        await MainActor.run {
            isBatchRunning = false
            if wasCancelled {
                cleanResultMessage = "已停止。已补全 \(successCount)/\(books.count) 本"
            } else {
                cleanResultMessage = "完成！\(successCount)/\(books.count) 本微信读书图书成功补全信息"
            }
            showingCleanResult = true
        }
    }

    /// 通用批量补全逻辑
    /// - Parameters:
    ///   - bookIDs: 待处理书籍的 PersistentIdentifier 列表
    ///   - label: 日志标签（"paper" / "weread"）
    ///   - emptyMessage: 无需补全时的提示
    ///   - doneMessage: 完成时的提示（参数: successCount, totalCount）
    private func batchEnrich(
        bookIDs: [SwiftData.PersistentIdentifier],
        label: String,
        emptyMessage: String,
        doneMessage: @Sendable (Int, Int) -> String
    ) async {
        guard !bookIDs.isEmpty else {
            cleanResultMessage = emptyMessage
            showingCleanResult = true
            return
        }

        // 建立本地作者简介缓存（主线程读一次）
        var localAuthorCache: [String: String] = [:]
        for book in allBooks where !book.isArchived {
            if let desc = book.authorDescription, !desc.isEmpty {
                let trimmed = book.author.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && localAuthorCache[trimmed] == nil {
                    localAuthorCache[trimmed] = desc
                }
            }
        }

        isBatchRunning = true
        batchTotal = bookIDs.count
        batchCurrent = 0
        batchProgress = 0
        batchStatusText = "正在批量补全..."

        let container = modelContext.container
        let totalCount = bookIDs.count
        let batchSaveInterval = 50

        let (successCount, processedCount, wasCancelled) = await Task.detached(priority: .utility) {
            let bgContext = ModelContext(container)
            bgContext.autosaveEnabled = false
            let lookupService = ISBNLookupService()
            var success = 0
            var processed = 0

            for (index, bookID) in bookIDs.enumerated() {
                if await MainActor.run(body: { self.batchCancelled }) { break }

                guard let book = bgContext.model(for: bookID) as? Book else { continue }
                let title = book.title

                await MainActor.run {
                    self.batchCurrent = index + 1
                    self.batchProgress = Double(index + 1) / Double(totalCount)
                    self.batchStatusText = "正在补全（\(title)）\(index + 1)/\(totalCount)"
                }

                // 本地作者简介缓存
                if (book.authorDescription ?? "").isEmpty {
                    let primaryAuthor = book.author.trimmingCharacters(in: .whitespaces)
                    if let localDesc = localAuthorCache[primaryAuthor] {
                        book.authorDescription = localDesc
                    }
                }

                // smartFill — 网络 I/O
                guard !Task.isCancelled else { break }
                let tFill0 = CFAbsoluteTimeGetCurrent()
                let result = await lookupService.smartFill(
                    isbn: book.isbn ?? "",
                    title: book.title,
                    author: book.author,
                    needsTitle: false,
                    needsPublisher: (book.publisher ?? "").isEmpty,
                    needsPages: book.totalPages == 0,
                    needsPrice: (book.price ?? "").isEmpty,
                    needsPublishDate: book.publishDate == nil,
                    needsTranslator: (book.translator ?? "").isEmpty,
                    needsAuthor: book.author.isEmpty || book.author == "未知作者",
                    needsBookDesc: (book.bookDescription ?? "").isEmpty,
                    needsAuthorDesc: (book.authorDescription ?? "").isEmpty
                )
                let tFill1 = CFAbsoluteTimeGetCurrent()
                AppLogger.perf("\(label)[\(index+1)/\(totalCount)] \(book.title) | smartFill:\(Int((tFill1-tFill0)*1000))ms filled:\(result.hasAnyFill)", category: "BatchEnrich")

                if Task.isCancelled { break }
                if await MainActor.run(body: { self.batchCancelled }) { break }

                // 应用结果
                if let p = result.publisher { book.publisher = p }
                if let p = result.totalPages { book.totalPages = p }
                if let p = result.price { book.price = p }
                if let d = result.publishDate { book.publishDate = self.parsePublishDate(d) }
                if let t = result.translator { book.translator = t }
                if let a = result.author { book.author = a }
                if let d = result.bookDescription { book.bookDescription = d }
                if let d = result.authorDescription {
                    book.authorDescription = d
                    let primaryAuthor = book.author.trimmingCharacters(in: .whitespaces)
                    if !primaryAuthor.isEmpty { localAuthorCache[primaryAuthor] = d }
                }
                book.lastEnrichmentDate = Date()
                if result.hasAnyFill { success += 1 }
                processed = index + 1

                // 低频 save
                if (index + 1) % batchSaveInterval == 0 {
                    let tSave0 = CFAbsoluteTimeGetCurrent()
                    try? bgContext.save()
                    let tSave1 = CFAbsoluteTimeGetCurrent()
                    AppLogger.perf("\(label) SAVE batch \(index+1) | \(Int((tSave1-tSave0)*1000))ms", category: "BatchEnrich")
                }

                // 限速：5 秒
                try? await Task.sleep(for: .seconds(5))
            }

            try? bgContext.save()
            let cancelled = await MainActor.run(body: { self.batchCancelled })
            return (success, processed, cancelled)
        }.value

        isBatchRunning = false
        batchTask = nil
        batchCancelled = false

        if wasCancelled {
            cleanResultMessage = "已停止。已补全 \(successCount)/\(processedCount) 本（共 \(totalCount) 本待处理）"
        } else {
            cleanResultMessage = doneMessage(successCount, totalCount)
        }
        showingCleanResult = true
    }

    /// 解析出版日期字符串
    private func parsePublishDate(_ dateString: String) -> Date? {
        let formatters: [String] = ["yyyy-MM-dd", "yyyy-MM", "yyyy"]
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }
}

// MARK: - 关联图书列表

struct ItemBooksView: View {
    let itemName: String
    let fieldType: Int  // 0=作者, 1=出版社, 2=标签
    let allBooks: [Book]

    private var books: [Book] {
        switch fieldType {
        case 0:
            return allBooks.filter { !$0.isArchived && $0.author.components(separatedBy: ", ").contains(itemName) }
        case 1:
            return allBooks.filter { !$0.isArchived && ($0.publisher?.components(separatedBy: ", ").contains(itemName) ?? false) }
        default:
            return allBooks.filter { !$0.isArchived && ($0.tags ?? []).contains(where: { $0.name == itemName }) }
        }
    }

    var body: some View {
        List(books) { book in
            HStack {
                // 封面缩略图
                if let data = book.coverImageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 36, height: 50)
                        .overlay {
                            Image(systemName: "book.closed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(book.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle(itemName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helper Model

struct NameCountItem: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

#Preview {
    NavigationStack {
        DataMaintenanceView()
    }
    .modelContainer(for: [Book.self, Tag.self], inMemory: true)
}
