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
    @State private var cachedAuthors: [NameCountItem]?
    @State private var cachedPublishers: [NameCountItem]?
    @State private var cachedTags: [NameCountItem]?

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
    @State private var batchSummary: EnrichmentBatchSummary?
    @State private var isBatchRunning = false
    @State private var batchTask: Task<Void, Never>?
    @State private var batchCancelled = false  // 手动取消标志（跨 Task.detached）
    @State private var aiAvailability = AIConfigAvailability.shared

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
            } else if cachedAuthors == nil {
                Spacer()
                ProgressView("加载中…")
                Spacer()
            } else {
                dataListView
            }
        }
        .navigationTitle("数据维护")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            aiAvailability.refresh()
            rebuildCaches()
        }
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
                    if isBatchRunning {
                        batchCancelled = true
                        batchTask?.cancel()
                        batchStatusText = "正在停止…"
                    } else {
                        batchCancelled = false
                        batchTask = Task { await batchEnrichPaperBooks() }
                    }
                } label: {
                    HStack {
                        Label(
                            isBatchRunning ? (batchCancelled ? "正在停止…" : "停止补全") : "批量补全纸质书信息",
                            systemImage: isBatchRunning ? "stop.circle" : "book.closed"
                        )
                        .foregroundStyle(isBatchRunning ? .red : .accentColor)
                        Spacer()
                        if isBatchRunning {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isCleaning || batchCancelled)

                Button {
                    batchCancelled = false
                    batchTask = Task { await batchAIEnrichBooks() }
                } label: {
                    Label("批量 AI 智能补全", systemImage: "sparkles")
                }
                .disabled(isCleaning || isBatchRunning || !aiAvailability.isAvailable)

                if EnrichmentBatchPolicy.shouldShowAISettingsLink(
                    isAIAvailable: aiAvailability.isAvailable
                ) {
                    NavigationLink("配置 AI 智能补全") {
                        AISettingsView()
                    }
                }
            } header: {
                Text("信息补全")
            } footer: {
                Text("普通补全按豆瓣 → Goodreads → Open Library 处理纸质书，并自动使用 AI 兜底；AI 批量补全适用于所有未归档载体。")
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
                        if let batchSummary {
                            Text(batchSummary.progressMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

    private func rebuildCaches() {
        let container = modelContext.container
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let booksFetch = FetchDescriptor<Book>()
            let tagsFetch = FetchDescriptor<Tag>()
            guard let books = try? context.fetch(booksFetch),
                  let tags = try? context.fetch(tagsFetch) else { return }

            var authorDict: [String: Int] = [:]
            var publisherDict: [String: Int] = [:]
            for book in books where !book.isArchived {
                let authors = book.author.components(separatedBy: ", ")
                for name in authors {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && trimmed != "未知作者" {
                        authorDict[trimmed, default: 0] += 1
                    }
                }
                if let p = book.publisher, !p.isEmpty {
                    let publishers = p.components(separatedBy: ", ")
                    for name in publishers {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            publisherDict[trimmed, default: 0] += 1
                        }
                    }
                }
            }

            let authors = authorDict.map { NameCountItem(name: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
            let publishers = publisherDict.map { NameCountItem(name: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }
            let tagCounts = tags.map { tag -> NameCountItem in
                let count = (tag.books ?? []).filter { !$0.isArchived }.count
                return NameCountItem(name: tag.name, count: count)
            }.sorted { $0.count > $1.count }

            await MainActor.run {
                self.cachedAuthors = authors
                self.cachedPublishers = publishers
                self.cachedTags = tagCounts
            }
        }
    }

    private var currentItems: [NameCountItem] {
        switch selectedTab {
        case 0: return cachedAuthors ?? []
        case 1: return cachedPublishers ?? []
        default: return cachedTags ?? []
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
            rebuildCaches()
        }
    }

    private func deleteTag(named name: String) {
        guard let tag = allTags.first(where: { $0.name == name }) else { return }
        modelContext.delete(tag)
        try? modelContext.save()
        rebuildCaches()
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
        rebuildCaches()
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
        if updatedCount > 0 { rebuildCaches() }
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
        if totalFixes > 0 { rebuildCaches() }
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
        let bookIDs = allBooks.filter { EnrichmentBatchPolicy.isCandidate($0, mode: .full) }
            .map(\.persistentModelID)

        await batchEnrich(
            bookIDs: bookIDs,
            mode: .full,
            label: "paper",
            emptyMessage: "所有纸质书信息已完整，无需补全"
        )
    }

    private func batchAIEnrichBooks() async {
        let bookIDs = allBooks.filter { EnrichmentBatchPolicy.isCandidate($0, mode: .aiOnly) }
            .map(\.persistentModelID)

        await batchEnrich(
            bookIDs: bookIDs,
            mode: .aiOnly,
            label: "ai",
            emptyMessage: "所有未归档图书均无需 AI 补全"
        )
    }

    /// 通用批量补全逻辑
    /// - Parameters:
    ///   - bookIDs: 待处理书籍的 PersistentIdentifier 列表
    ///   - label: 日志标签（"paper" / "weread"）
    ///   - emptyMessage: 无需补全时的提示
    private func batchEnrich(
        bookIDs: [SwiftData.PersistentIdentifier],
        mode: EnrichmentMode,
        label: String,
        emptyMessage: String
    ) async {
        guard !bookIDs.isEmpty else {
            cleanResultMessage = emptyMessage
            showingCleanResult = true
            return
        }

        // 建立本地作者简介缓存（主线程读一次，并发任务中只读不写）
        let localAuthorCache: [String: String] = {
            var cache: [String: String] = [:]
            for book in allBooks where !book.isArchived {
                if let desc = book.authorDescription, !desc.isEmpty {
                    let trimmed = book.author.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && cache[trimmed] == nil {
                        cache[trimmed] = desc
                    }
                }
            }
            return cache
        }()

        isBatchRunning = true
        batchTotal = bookIDs.count
        batchCurrent = 0
        batchProgress = 0
        batchStatusText = "正在批量补全..."
        batchSummary = EnrichmentBatchSummary(totalCount: bookIDs.count)

        let container = modelContext.container
        let totalCount = bookIDs.count
        let perBookSleepSeconds = EnrichmentBatchPolicy.interBookDelaySeconds(for: mode)

        await BatchEnrichmentState.shared.start()

        // 启用电池监听以便 SystemMetrics.snapshot() 读取电量
        await MainActor.run { UIDevice.current.isBatteryMonitoringEnabled = true }

        // 启动定期 metrics 采样（每 15 秒）+ thermal state 变化监听（仅 verbose 模式记录）
        let metricsTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                let snapshot = await MainActor.run { SystemMetrics.snapshot() }
                AppLogger.perf("batch metrics: \(snapshot)", category: "BatchEnrich")
                try? await Task.sleep(for: .seconds(15))
            }
        }

        // thermal state 变化时立即记录（即使两次采样间也不漏）
        let thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            AppLogger.perf("thermal CHANGE: \(SystemMetrics.thermalStateString)", category: "BatchEnrich")
        }

        let detachedTask = Task.detached(priority: .utility) {
            let coordinator = EnrichmentCoordinator.live()
            var summary = EnrichmentBatchSummary(totalCount: totalCount)

            // 顺序处理；普通来源保留间隔，纯 AI 模式由远端请求本身控制节奏
            // 不并发——并发 + 多源 HTTP 会导致 modem/CPU 持续高峰，手机过热
            for (index, bookID) in bookIDs.enumerated() {
                if Task.isCancelled { break }

                guard let snapshot = EnrichmentBookPersistence.eligibleBatchSnapshot(
                    for: bookID,
                    mode: mode,
                    in: container
                ) else { continue }
                let title = snapshot.draft.title

                let primaryAuthor = snapshot.draft.author.trimmingCharacters(in: .whitespaces)
                let localAuthorDescription = localAuthorCache[primaryAuthor]

                if Task.isCancelled { break }

                // 进度 UI（处理本本前显示当前书）
                let displayIndex = summary.completedCount + 1
                await MainActor.run {
                    self.batchStatusText = "正在补全（\(title)）\(displayIndex)/\(totalCount)"
                }

                let tFill0 = CFAbsoluteTimeGetCurrent()
                let outcome = await coordinator.enrich(
                    snapshot.draft,
                    mode: mode,
                    localAuthorDescription: localAuthorDescription
                )
                let tFill1 = CFAbsoluteTimeGetCurrent()
                AppLogger.perf("\(label)[\(index+1)/\(totalCount)] \(title) | enrich:\(Int((tFill1-tFill0)*1000))ms fields:\(outcome.changedFields.count)", category: "BatchEnrich")

                guard let committedOutcome = try? EnrichmentBookPersistence.commitBatch(
                    outcome,
                    to: bookID,
                    mode: mode,
                    in: container
                ) else { continue }

                summary.record(committedOutcome)
                let currentSummary = summary
                await MainActor.run {
                    self.batchSummary = currentSummary
                    self.batchCurrent = currentSummary.completedCount
                    self.batchProgress = Double(currentSummary.completedCount) / Double(totalCount)
                }

                if Task.isCancelled
                    || committedOutcome.termination == .cancelled
                    || AIEnrichmentAttemptPolicy.shouldStopBatch(for: committedOutcome.aiStatus) {
                    break
                }

                // 普通来源每本间隔 2 秒；纯 AI 调用不另加固定等待
                if index < bookIDs.count - 1, perBookSleepSeconds > 0 {
                    try? await Task.sleep(for: .seconds(perBookSleepSeconds))
                }
            }

            let cancelled = Task.isCancelled
            return (summary, cancelled)
        }

        // 当外层 task 被取消（用户点停止）时，把取消传播到 detached task
        let (summary, wasCancelled) = await EnrichmentBackgroundExecution().run(
            named: mode == .aiOnly ? "批量 AI 智能补全" : "批量补全图书信息"
        ) {
            await withTaskCancellationHandler {
                await detachedTask.value
            } onCancel: {
                detachedTask.cancel()
            }
        }

        // 停止 metrics 采集
        metricsTask.cancel()
        NotificationCenter.default.removeObserver(thermalObserver)

        await BatchEnrichmentState.shared.stop()

        isBatchRunning = false
        batchTask = nil
        batchCancelled = false
        batchSummary = summary

        if wasCancelled {
            cleanResultMessage = "已停止。已处理 \(summary.completedCount)/\(totalCount) 本；\(summary.message)"
        } else {
            cleanResultMessage = "完成！\(summary.message)"
        }
        showingCleanResult = true
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
