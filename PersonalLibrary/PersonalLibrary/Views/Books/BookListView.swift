import SwiftUI
import SwiftData
import os.log

private let perfLog = Logger(subsystem: "com.example.PersonalLibrary", category: "ListPerf")

// MARK: - 搜索范围

enum SearchScope: CaseIterable {
    case all, title, author, tag, publisher, shelf

    var label: String {
        switch self {
        case .all: return "全部"
        case .title: return "书名"
        case .author: return "作者"
        case .tag: return "标签"
        case .publisher: return "出版社"
        case .shelf: return "书架"
        }
    }

    var placeholder: String {
        switch self {
        case .all: return "搜索书名、作者、标签、出版社..."
        case .title: return "搜索书名"
        case .author: return "搜索作者"
        case .tag: return "搜索标签"
        case .publisher: return "搜索出版社"
        case .shelf: return "搜索书架名称"
        }
    }
}

struct BookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @Query(sort: \Bookshelf.name) private var bookshelves: [Bookshelf]
    @Query private var allTags: [Tag]
    @State private var showingAddBook = false
    @State private var searchText = ""
    @State private var searchScope: SearchScope = .all
    @State private var selectedShelf: String = "我的藏书"

    // 多选相关
    @State private var isSelecting = false
    @State private var selectedBooks: Set<PersistentIdentifier> = []
    @State private var showTagSheet = false
    @State private var showMoveSheet = false
    @State private var showStatusSheet = false
    @State private var showRatingSheet = false
    @State private var showAdvancedSearch = false

    // 高级搜索结果
    @State private var advancedSearchResults: [Book]?

    // 纸质书筛选（默认开启，持久化）
    @AppStorage("bookList_paperOnly") private var paperOnly = true

    // 快速标签（滑动操作）
    @State private var bookForQuickTag: Book?
    // 标记已读后评分
    @State private var bookForRating: Book?

    // 缓存：避免每帧重算（relationship fault 是主线程 I/O）
    @State private var cachedShelfNames: [String] = ["我的藏书"]
    @State private var cachedFilteredBooks: [Book] = []
    // 标记首次加载
    @State private var needsInitialLoad = true

    /// 当前筛选后的书籍（读缓存）
    private var filteredBooks: [Book] {
        cachedFilteredBooks
    }

    /// 当前选中的 Book 对象
    private var selectedBookObjects: [Book] {
        books.filter { selectedBooks.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索栏
                searchBar

                // 书架切换栏
                shelfTabBar

                Divider()

                // 书籍列表
                bookList

                // 多选操作栏
                if isSelecting && !selectedBooks.isEmpty {
                    batchActionBar
                }
            }
            .onAppear {
                // 从 BookDetailView 返回时刷新（用户可能改了状态）
                if !needsInitialLoad {
                    recomputeFilteredBooks()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isSelecting ? "已选 \(selectedBooks.count) 本" : "我的藏书")
                        .font(.headline)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelecting {
                        Button("取消") {
                            exitSelectMode()
                        }
                    } else {
                        Button("选择") {
                            isSelecting = true
                        }
                        .disabled(books.isEmpty)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSelecting {
                        Button(selectedBooks.count == filteredBooks.count ? "取消全选" : "全选") {
                            if selectedBooks.count == filteredBooks.count {
                                selectedBooks.removeAll()
                            } else {
                                selectedBooks = Set(filteredBooks.map(\.persistentModelID))
                            }
                        }
                    } else {
                        Button(action: { showingAddBook = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddBook) {
                AddBookView()
            }
            .sheet(isPresented: $showAdvancedSearch) {
                AdvancedSearchView { results in
                    advancedSearchResults = results
                }
            }
            .sheet(isPresented: $showTagSheet) {
                BatchTagView(books: selectedBookObjects) {
                    exitSelectMode()
                }
            }
            .sheet(isPresented: $showMoveSheet) {
                BatchMoveShelfView(books: selectedBookObjects) {
                    exitSelectMode()
                }
            }
            .sheet(isPresented: $showStatusSheet) {
                BatchStatusView(books: selectedBookObjects) {
                    exitSelectMode()
                }
            }
            .sheet(isPresented: $showRatingSheet) {
                BatchRatingView(books: selectedBookObjects) {
                    exitSelectMode()
                }
            }
            .sheet(item: $bookForQuickTag) { book in
                QuickTagView(book: book)
            }
            .sheet(item: $bookForRating) { book in
                MarkReadRatingView(book: book)
            }
            .overlay {
                if books.isEmpty {
                    ContentUnavailableView(
                        "书架是空的",
                        systemImage: "books.vertical",
                        description: Text("点击右上角 + 添加你的第一本书")
                    )
                }
            }
            .onChange(of: selectedShelf) { _, _ in
                advancedSearchResults = nil
                recomputeFilteredBooks()
            }
            .onChange(of: searchText) { _, _ in
                advancedSearchResults = nil
                recomputeFilteredBooks()
            }
            .onChange(of: searchScope) { _, _ in recomputeFilteredBooks() }
            .onChange(of: paperOnly) { _, _ in recomputeFilteredBooks() }
            .onChange(of: advancedSearchResults) { _, _ in recomputeFilteredBooks() }
            .onChange(of: books.count) { _, _ in
                recomputeShelfNames()
                recomputeFilteredBooks()
            }
            .onChange(of: bookshelves.count) { _, _ in recomputeShelfNames() }
            .task {
                if needsInitialLoad {
                    needsInitialLoad = false
                    recomputeShelfNames()
                    recomputeFilteredBooks()
                }
            }
            // 当 sheet dismiss 后（标记已读、批量操作等），刷新列表
            .onChange(of: bookForRating) { _, new in
                if new == nil { recomputeFilteredBooks() }
            }
            .onChange(of: bookForQuickTag) { _, new in
                if new == nil { recomputeFilteredBooks() }
            }
            .onChange(of: isSelecting) { _, new in
                if !new { recomputeFilteredBooks() }
            }
        }
    }

    private func exitSelectMode() {
        isSelecting = false
        selectedBooks.removeAll()
    }

    // MARK: - 缓存重算

    private func recomputeShelfNames() {
        var names: [String] = ["我的藏书"]

        // 直接使用 @Query(sort: \Bookshelf.name) 的顺序，与书架 tab 保持一致
        for shelf in bookshelves where shelf.name != "微信读书" {
            if !names.contains(shelf.name) {
                names.append(shelf.name)
            }
        }

        // 微信读书虚拟书架 — 只查 tag name，不遍历所有 book.tags
        let hasWeRead = allTags.contains { $0.name == "微信读书" }
        if hasWeRead && !names.contains("微信读书") {
            names.append("微信读书")
        }

        cachedShelfNames = names
    }

    private func recomputeFilteredBooks() {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            perfLog.info("recomputeFilteredBooks: \(ms)ms count:\(cachedFilteredBooks.count)")
            FileLogger.shared.log("recompute: \(ms)ms count:\(cachedFilteredBooks.count) shelf:\(selectedShelf)")
        }
        if let advResults = advancedSearchResults {
            cachedFilteredBooks = advResults
            return
        }

        var result: [Book]

        if selectedShelf == "我的藏书" {
            result = books.filter { !$0.isArchived }
        } else if selectedShelf == "微信读书" {
            result = books.filter { book in
                !book.isArchived && book.wereadBookId != nil
            }
        } else {
            // 用反向关系：从 Bookshelf.books 取，避免遍历全部 2311 本触发 relationship fault
            if let shelf = bookshelves.first(where: { $0.name == selectedShelf }) {
                result = (shelf.books ?? []).filter { !$0.isArchived }
                // 保持与 @Query 一致的排序（addedDate 降序）
                result.sort { $0.addedDate > $1.addedDate }
            } else {
                result = []
            }
        }

        if paperOnly && selectedShelf == "我的藏书" {
            result = result.filter { $0.bookType == .paper }
        }

        if !searchText.isEmpty {
            let query = searchText
            result = result.filter { book in
                switch searchScope {
                case .all:
                    return matchesGlobal(book: book, query: query)
                case .title:
                    return book.title.localizedCaseInsensitiveContains(query)
                case .author:
                    return book.author.localizedCaseInsensitiveContains(query)
                case .tag:
                    return book.tags?.contains(where: { $0.name.localizedCaseInsensitiveContains(query) }) == true
                case .publisher:
                    return book.publisher?.localizedCaseInsensitiveContains(query) == true
                case .shelf:
                    return book.bookshelf?.name.localizedCaseInsensitiveContains(query) == true
                }
            }
        }

        cachedFilteredBooks = result
    }

    /// 全局搜索：匹配书名、作者、出版社、标签、书架、ISBN
    private func matchesGlobal(book: Book, query: String) -> Bool {
        if book.title.localizedCaseInsensitiveContains(query) { return true }
        if book.author.localizedCaseInsensitiveContains(query) { return true }
        if book.publisher?.localizedCaseInsensitiveContains(query) == true { return true }
        if book.isbn?.localizedCaseInsensitiveContains(query) == true { return true }
        if book.bookshelf?.name.localizedCaseInsensitiveContains(query) == true { return true }
        if book.tags?.contains(where: { $0.name.localizedCaseInsensitiveContains(query) }) == true { return true }
        if book.translator?.localizedCaseInsensitiveContains(query) == true { return true }
        return false
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(searchScope.placeholder, text: $searchText)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // 高级搜索按钮
                Button {
                    showAdvancedSearch = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                        .foregroundStyle(.orange)
                }
            }

            // 搜索范围选择
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        searchScopeChip(scope: scope)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func searchScopeChip(scope: SearchScope) -> some View {
        let isActive = searchScope == scope
        return Text(scope.label)
            .font(.caption)
            .fontWeight(isActive ? .semibold : .regular)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? Color.orange.opacity(0.15) : Color(.systemGray6))
            .foregroundStyle(isActive ? .orange : .secondary)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onTapGesture {
                searchScope = scope
            }
    }

    // MARK: - 书架切换栏

    private var shelfTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(cachedShelfNames, id: \.self) { name in
                    shelfTab(name: name)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
    }

    private func shelfTab(name: String) -> some View {
        let isSelected = selectedShelf == name
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                // 纸质书筛选按钮（紧跟"我的藏书"文字后面）
                if name == "我的藏书" {
                    Button {
                        paperOnly.toggle()
                    } label: {
                        Image(systemName: paperOnly ? "book.fill" : "book")
                            .font(.caption)
                            .foregroundStyle(paperOnly ? .orange : .secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? Color.orange : Color.clear)
                .frame(height: 3)
                .padding(.horizontal, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedShelf = name
        }
    }

    // MARK: - 书籍列表

    private var bookList: some View {
        List {
            ForEach(filteredBooks) { book in
                if isSelecting {
                    selectableBookRow(book: book)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                } else {
                    NavigationLink(destination: BookDetailView(book: book)) {
                        BookRowView(book: book)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            bookForRating = book
                        } label: {
                            Label("已读", systemImage: "checkmark")
                        }
                        .tint(.green)

                        Button {
                            bookForQuickTag = book
                        } label: {
                            Label("标签", systemImage: "tag")
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button {
                            isSelecting = true
                            selectedBooks.insert(book.persistentModelID)
                        } label: {
                            Label("多选", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }


    private func selectableBookRow(book: Book) -> some View {
        SelectableBookRow(
            book: book,
            isSelected: selectedBooks.contains(book.persistentModelID),
            onToggle: {
                if selectedBooks.contains(book.persistentModelID) {
                    selectedBooks.remove(book.persistentModelID)
                } else {
                    selectedBooks.insert(book.persistentModelID)
                }
            }
        )
    }

    // MARK: - 批量操作栏

    private var batchActionBar: some View {
        BatchActionBar(
            onTag: { showTagSheet = true },
            onMove: { showMoveSheet = true },
            onStatus: { showStatusSheet = true },
            onRating: { showRatingSheet = true }
        )
    }
}

// MARK: - 书籍行视图

struct BookRowView: View {
    let book: Book
    @State private var coverImage: UIImage?
    @State private var fetchTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 封面
            bookCover
                .frame(width: 60, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 1)

            // 信息区域
            VStack(alignment: .leading, spacing: 5) {
                // 书名 + 书架
                HStack(alignment: .top) {
                    Text(book.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if let shelfName = book.bookshelf?.name {
                        Text(shelfName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                }

                // 作者
                Text(formatAuthor(book.author))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // 状态 + 类型 + 标签
                infoTagsRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear {
            let t0 = CFAbsoluteTimeGetCurrent()
            let _ = book.bookshelf?.name
            let t1 = CFAbsoluteTimeGetCurrent()
            let _ = book.tags?.count
            let t2 = CFAbsoluteTimeGetCurrent()
            let shelfMs = Int((t1 - t0) * 1000)
            let tagsMs = Int((t2 - t1) * 1000)
            if shelfMs > 1 || tagsMs > 1 {
                perfLog.warning("ROW FAULT \(book.title) | shelf:\(shelfMs)ms tags:\(tagsMs)ms")
                FileLogger.shared.log("ROW FAULT \(book.title) | shelf:\(shelfMs)ms tags:\(tagsMs)ms")
            }
            loadCoverOnAppear()
        }
        .onDisappear { cancelFetch() }
        .onChange(of: book.coverImageData) { _, newData in
            // 封面被编辑后，清除缓存并刷新
            let cacheKey = "\(book.title)|\(book.author)"
            if let data = newData, let img = UIImage(data: data) {
                CoverImageCache.shared.set(img, for: cacheKey)
                coverImage = img
            } else {
                CoverImageCache.shared.remove(for: cacheKey)
                coverImage = nil
            }
        }
    }

    // MARK: - 状态/类型/标签行

    private var infoTagsRow: some View {
        FlowLayout(spacing: 5) {
            // 阅读状态 — 只显示"已读"
            if book.status == .finished {
                StatusBadge(status: book.status)
            }

            // 书籍类型（非纸质书才显示）
            if book.bookType != .paper {
                Text(book.bookType.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.12))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
            }

            // 出版社
            if let publisher = book.publisher, !publisher.isEmpty {
                Text(publisher)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // 用户标签 — 全部显示，自动换行
            if let tags = book.tags, !tags.isEmpty {
                ForEach(tags) { tag in
                    Text("#\(tag.name)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - 封面

    @ViewBuilder
    private var bookCover: some View {
        if let image = coverImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            coverPlaceholder
        }
    }

    /// 行出现时加载封面 — 全异步 + debounce，滚动时不触发 I/O
    private func loadCoverOnAppear() {
        if coverImage != nil { return }

        let cacheKey = "\(book.title)|\(book.author)"

        // 1. 内存缓存命中 → 零开销，同步返回
        if let cached = CoverImageCache.shared.image(for: cacheKey) {
            coverImage = cached
            return
        }

        // 2. debounce 150-300ms（随机抖动，避免一屏多本同时醒来触发批量 layout）
        fetchTask = Task {
            let jitter = Int.random(in: 150...300)
            try? await Task.sleep(for: .milliseconds(jitter))
            guard !Task.isCancelled else { return }

            // Layer 3 修复：将 externalStorage 读取移到后台线程
            // book.coverImageData 会触发 SQLite fault，不能在主线程做
            let hasCover = book.hasCoverData
            let bookTitle = book.title
            let coverURL = book.coverImageURL
            let isbn = book.isbn
            let doubanURL = book.doubanURL
            let author = book.author

            if hasCover {
                let t0 = CFAbsoluteTimeGetCurrent()
                // externalStorage 读 + 解码全部在后台线程
                let img = await Task.detached(priority: .utility) {
                    let data = book.coverImageData
                    guard let data else { return nil as UIImage? }
                    return UIImage(data: data)
                }.value
                let t1 = CFAbsoluteTimeGetCurrent()
                perfLog.debug("cover DB \(bookTitle) | total:\(Int((t1-t0)*1000))ms")
                FileLogger.shared.log("cover DB \(bookTitle) | total:\(Int((t1-t0)*1000))ms")
                guard let img, !Task.isCancelled else { return }
                CoverImageCache.shared.set(img, for: cacheKey)
                coverImage = img
                return
            }

            // 无本地数据 → 再等 350ms 网络下载（总共 500ms debounce）
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            let tNet0 = CFAbsoluteTimeGetCurrent()
            let data = await CoverFetchService.shared.fetchCoverThrottled(
                coverImageURL: coverURL,
                isbn: isbn,
                doubanURL: doubanURL,
                title: bookTitle,
                author: author
            )
            let tNet1 = CFAbsoluteTimeGetCurrent()
            perfLog.debug("cover NET \(bookTitle) | time:\(Int((tNet1-tNet0)*1000))ms got:\(data?.count ?? 0)")
            FileLogger.shared.log("cover NET \(bookTitle) | time:\(Int((tNet1-tNet0)*1000))ms got:\(data?.count ?? 0)")

            guard let data, !Task.isCancelled else { return }
            let img = await Task.detached(priority: .utility) {
                UIImage(data: data)
            }.value
            guard let img, !Task.isCancelled else { return }

            CoverImageCache.shared.set(img, for: cacheKey)
            coverImage = img
            // 不在列表写入 book.coverImageData — 避免滚动时多次 DB 写入触发
            // @Query 级联刷新导致卡顿。持久化由详情页/编辑页按需完成。
        }
    }

    private func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(.systemGray5))
            .overlay {
                Image(systemName: "book.closed")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }


    // MARK: - 格式化作者

    private func formatAuthor(_ author: String) -> String {
        // 兼容旧数据：如果还含有分号，用逗号替换显示
        author
            .replacingOccurrences(of: "；", with: ", ")
            .replacingOccurrences(of: ";", with: ", ")
    }
}

// MARK: - 阅读状态标签

struct StatusBadge: View {
    let status: ReadingStatus

    var color: Color {
        switch status {
        case .reading: return .blue
        case .finished: return .green
        case .wishlist: return .purple
        case .dropped: return .red
        case .idle: return .gray
        }
    }

    var body: some View {
        Text(status.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - 批量打标签

struct BatchTagView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingTags: [Tag]
    let books: [Book]
    let onDone: () -> Void
    @State private var selectedTags: Set<String> = []
    @State private var newTagName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("新建标签") {
                    HStack {
                        TextField("输入标签名", text: $newTagName)
                        Button("添加") {
                            addNewTag()
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("已有标签") {
                    ForEach(existingTags) { tag in
                        HStack {
                            Text(tag.name)
                            Spacer()
                            if selectedTags.contains(tag.name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedTags.contains(tag.name) {
                                selectedTags.remove(tag.name)
                            } else {
                                selectedTags.insert(tag.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle("为 \(books.count) 本书打标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        applyTags()
                    }
                    .disabled(selectedTags.isEmpty)
                }
            }
        }
    }

    private func addNewTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        selectedTags.insert(trimmed)
        // 如果标签不存在就创建
        if !existingTags.contains(where: { $0.name == trimmed }) {
            let tag = Tag(name: trimmed)
            modelContext.insert(tag)
        }
        newTagName = ""
    }

    private func applyTags() {
        let container = modelContext.container
        let bookIDs = books.map(\.persistentModelID)
        let tagNames = Array(selectedTags)

        dismiss()

        Task {
            await Task.detached(priority: .userInitiated) {
                let bgContext = ModelContext(container)
                bgContext.autosaveEnabled = false

                // 获取或创建标签
                var tagMap: [String: Tag] = [:]
                let allTags = (try? bgContext.fetch(FetchDescriptor<Tag>())) ?? []
                for tag in allTags {
                    tagMap[tag.name] = tag
                }
                for name in tagNames where tagMap[name] == nil {
                    let newTag = Tag(name: name)
                    bgContext.insert(newTag)
                    tagMap[name] = newTag
                }

                // 给每本书打标签
                for id in bookIDs {
                    guard let book = bgContext.model(for: id) as? Book else { continue }
                    var bookTags = book.tags ?? []
                    for name in tagNames {
                        if !bookTags.contains(where: { $0.name == name }),
                           let tag = tagMap[name] {
                            bookTags.append(tag)
                        }
                    }
                    book.tags = bookTags
                }

                try? bgContext.save()
            }.value

            await MainActor.run { onDone() }
        }
    }
}

// MARK: - 批量移动书架

struct BatchMoveShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bookshelf.name) private var bookshelves: [Bookshelf]
    let books: [Book]
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // 移出书架（设为未分类）
                HStack {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("移出书架（未分类）")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    moveBooks(to: nil)
                }

                // 各个书架
                ForEach(bookshelves) { shelf in
                    HStack {
                        Image(systemName: shelf.icon)
                            .foregroundStyle(.orange)
                        Text(shelf.name)
                        Spacer()
                        Text("\(shelf.books?.count ?? 0) 本")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        moveBooks(to: shelf)
                    }
                }
            }
            .navigationTitle("移动 \(books.count) 本书到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func moveBooks(to shelf: Bookshelf?) {
        for book in books {
            book.bookshelf = shelf
        }
        dismiss()
        onDone()
    }
}

// MARK: - 批量修改状态

struct BatchStatusView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let books: [Book]
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(ReadingStatus.allCases, id: \.self) { status in
                    HStack {
                        StatusBadge(status: status)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        applyStatus(status)
                    }
                }
            }
            .navigationTitle("修改 \(books.count) 本书状态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func applyStatus(_ status: ReadingStatus) {
        for book in books {
            book.status = status
            book.statusChangedDate = Date()
            if status == .finished {
                book.finishedDate = Date()
            }
        }
        dismiss()
        onDone()
    }
}

// MARK: - 批量评分

struct BatchRatingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let books: [Book]
    let onDone: () -> Void
    @State private var rating: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("为 \(books.count) 本书评分")
                    .font(.headline)
                    .padding(.top, 24)

                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.largeTitle)
                            .foregroundStyle(star <= rating ? .yellow : .gray.opacity(0.3))
                            .onTapGesture {
                                if rating == star {
                                    rating = 0
                                } else {
                                    rating = star
                                }
                            }
                    }
                }

                if rating == 0 {
                    Text("点击星星设定评分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("清除评分") {
                        rating = 0
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }

                Spacer()
            }
            .navigationTitle("评分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") { applyRating() }
                }
            }
        }
    }

    private func applyRating() {
        for book in books {
            book.rating = rating > 0 ? rating : nil
        }
        dismiss()
        onDone()
    }
}

// MARK: - 标记已读 + 评分

struct MarkReadRatingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var book: Book
    @State private var rating: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("标记「\(book.title)」为已读")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // 评分
                VStack(spacing: 8) {
                    Text("给这本书打个分？")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.title)
                                .foregroundStyle(star <= rating ? .yellow : .gray.opacity(0.3))
                                .onTapGesture {
                                    if rating == star {
                                        rating = 0
                                    } else {
                                        rating = star
                                    }
                                }
                        }
                    }

                    Text("可以不评分，直接点完成")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .navigationTitle("标记已读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        book.status = .finished
                        book.statusChangedDate = Date()
                        book.finishedDate = Date()
                        if rating > 0 {
                            book.rating = rating
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 快速打标签（滑动操作）

struct QuickTagView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingTags: [Tag]
    @Bindable var book: Book
    @State private var newTagName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("新建标签") {
                    HStack {
                        TextField("输入标签名", text: $newTagName)
                        Button("添加") {
                            addTag(name: newTagName)
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("已有标签") {
                    ForEach(existingTags) { tag in
                        let hasTag = book.tags?.contains(where: { $0.persistentModelID == tag.persistentModelID }) == true
                        HStack {
                            Text(tag.name)
                            Spacer()
                            if hasTag {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleTag(tag, hasTag: hasTag)
                        }
                    }
                }
            }
            .navigationTitle("为「\(book.title)」打标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func addTag(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var bookTags = book.tags ?? []
        if !bookTags.contains(where: { $0.name == trimmed }) {
            if let existing = existingTags.first(where: { $0.name == trimmed }) {
                bookTags.append(existing)
            } else {
                let newTag = Tag(name: trimmed)
                modelContext.insert(newTag)
                bookTags.append(newTag)
            }
            book.tags = bookTags
            try? modelContext.save()
        }
        newTagName = ""
    }

    private func toggleTag(_ tag: Tag, hasTag: Bool) {
        var bookTags = book.tags ?? []
        if hasTag {
            bookTags.removeAll { $0.persistentModelID == tag.persistentModelID }
        } else {
            bookTags.append(tag)
        }
        book.tags = bookTags
        try? modelContext.save()
    }
}

#Preview {
    BookListView()
        .modelContainer(for: [Book.self, Bookshelf.self, Tag.self, ReadingRecord.self], inMemory: true)
}
