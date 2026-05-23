import SwiftUI
import SwiftData

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
    @Query(sort: \Bookshelf.sortOrder) private var bookshelves: [Bookshelf]
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

    // 纸质书筛选（默认开启，持久化）
    @AppStorage("bookList_paperOnly") private var paperOnly = true

    // 快速标签（滑动操作）
    @State private var bookForQuickTag: Book?
    // 标记已读后评分
    @State private var bookForRating: Book?

    /// 获取所有可用的书架名称
    private var shelfNames: [String] {
        var names: [String] = ["我的藏书"]

        // 真实书架
        for shelf in bookshelves {
            if !names.contains(shelf.name) {
                names.append(shelf.name)
            }
        }

        // 微信读书虚拟书架
        let hasWeRead = books.contains { book in
            book.tags?.contains(where: { $0.name == "微信读书" }) == true
        }
        if hasWeRead && !names.contains("微信读书") {
            names.append("微信读书")
        }

        return names
    }

    /// 当前筛选后的书籍
    private var filteredBooks: [Book] {
        var result: [Book]

        if selectedShelf == "我的藏书" {
            result = books.filter { !$0.isArchived }
        } else if selectedShelf == "微信读书" {
            result = books.filter { book in
                !book.isArchived && book.tags?.contains(where: { $0.name == "微信读书" }) == true
            }
        } else {
            result = books.filter { !$0.isArchived && $0.bookshelf?.name == selectedShelf }
        }

        // 纸质书筛选（仅对"我的藏书"生效）
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

        return result
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
                AdvancedSearchView()
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
        }
    }

    private func exitSelectMode() {
        isSelecting = false
        selectedBooks.removeAll()
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
                ForEach(shelfNames, id: \.self) { name in
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
                    .buttonStyle(.plain)
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
                    .onLongPressGesture {
                        if !isSelecting {
                            isSelecting = true
                            selectedBooks.insert(book.persistentModelID)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }


    private func selectableBookRow(book: Book) -> some View {
        let isSelected = selectedBooks.contains(book.persistentModelID)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .orange : .secondary)
                .padding(.leading, 16)

            BookRowView(book: book)
                .padding(.leading, -16)  // 抵消 BookRowView 内部的 leading padding
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedBooks.remove(book.persistentModelID)
            } else {
                selectedBooks.insert(book.persistentModelID)
            }
        }
    }

    // MARK: - 批量操作栏

    private var batchActionBar: some View {
        HStack(spacing: 0) {
            batchButton(icon: "tag", label: "标签") {
                showTagSheet = true
            }
            batchButton(icon: "arrow.right.square", label: "移动") {
                showMoveSheet = true
            }
            batchButton(icon: "book", label: "状态") {
                showStatusSheet = true
            }
            batchButton(icon: "star", label: "评分") {
                showRatingSheet = true
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Divider() }
    }

    private func batchButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.orange)
        }
    }
}

// MARK: - 书籍行视图

struct BookRowView: View {
    @Environment(\.modelContext) private var modelContext
    let book: Book
    @State private var fetchedCoverData: Data?
    @State private var hasFetchedCover = false

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
        if let data = book.coverImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let data = fetchedCoverData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            coverPlaceholder
                .task(id: book.title) { await fetchAndCacheCover() }
        }
    }

    private func fetchAndCacheCover() async {
        guard !hasFetchedCover else { return }
        hasFetchedCover = true

        // 优先从 coverImageURL 直接下载（豆瓣图片需要 Referer）
        if let urlStr = book.coverImageURL, !urlStr.isEmpty {
            let data = await CoverFetchService.shared.downloadWithReferer(urlStr: urlStr)
            if let data, data.count > 100 {
                fetchedCoverData = data
                book.coverImageData = data
                // 不立即 save，由 SwiftData 自动合并或下次 save 时持久化
                return
            }
        }

        // 备用：通过豆瓣搜索、豆瓣页面、Open Library
        let data = await CoverFetchService.shared.fetchCover(
            isbn: book.isbn,
            doubanURL: book.doubanURL,
            title: book.title,
            author: book.author
        )
        if let data {
            fetchedCoverData = data
            book.coverImageData = data
        }
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
        for book in books {
            var bookTags = book.tags ?? []
            for tagName in selectedTags {
                if !bookTags.contains(where: { $0.name == tagName }) {
                    if let existing = existingTags.first(where: { $0.name == tagName }) {
                        bookTags.append(existing)
                    } else {
                        let newTag = Tag(name: tagName)
                        modelContext.insert(newTag)
                        bookTags.append(newTag)
                    }
                }
            }
            book.tags = bookTags
        }
        try? modelContext.save()
        dismiss()
        onDone()
    }
}

// MARK: - 批量移动书架

struct BatchMoveShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bookshelf.sortOrder) private var bookshelves: [Bookshelf]
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
        try? modelContext.save()
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
        try? modelContext.save()
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
        try? modelContext.save()
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
                        try? modelContext.save()
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
