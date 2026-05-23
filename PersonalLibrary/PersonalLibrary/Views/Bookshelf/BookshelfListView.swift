import SwiftUI
import SwiftData

/// 书架管理页面 — 展示所有书架（含微信读书虚拟书架），支持新增/删除
struct BookshelfListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Bookshelf.sortOrder) private var bookshelves: [Bookshelf]
    @Query private var allBooks: [Book]
    @State private var showingAddSheet = false
    @State private var shelfToDelete: Bookshelf?
    @State private var showDeleteAlert = false

    /// 微信读书虚拟书架的书籍（按 wereadBookId 判断，最可靠）
    private var weReadBooks: [Book] {
        allBooks.filter { $0.wereadBookId != nil }
    }

    /// 是否有微信读书书籍
    private var hasWeRead: Bool {
        !weReadBooks.isEmpty
    }

    /// 未分类书籍（无书架、未归档、且非微信读书导入的书）
    private var uncategorizedBooks: [Book] {
        allBooks.filter { $0.bookshelf == nil && !$0.isArchived && $0.wereadBookId == nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 顶部汇总
                    summaryHeader

                    // 书架列表
                    if !bookshelves.isEmpty {
                        shelvesSection
                    }

                    // 特殊入口
                    specialSection
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("书架")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddBookshelfView()
            }
            .alert("删除书架", isPresented: $showDeleteAlert) {
                Button("仅删除书架", role: .destructive) {
                    deleteShelf(withBooks: false)
                }
                Button("连同图书一起删除", role: .destructive) {
                    deleteShelf(withBooks: true)
                }
                Button("取消", role: .cancel) {
                    shelfToDelete = nil
                }
            } message: {
                if let shelf = shelfToDelete {
                    Text("书架「\(shelf.name)」中有 \(shelf.books?.count ?? 0) 本书。\n要一起删除这些图书吗？")
                }
            }
            .overlay {
                if bookshelves.isEmpty && !hasWeRead {
                    ContentUnavailableView(
                        "还没有书架",
                        systemImage: "square.stack.3d.up",
                        description: Text("点击右上角 + 创建你的第一个书架")
                    )
                }
            }
        }
    }

    // MARK: - 顶部汇总

    private var summaryHeader: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("\(bookshelves.count + (hasWeRead ? 1 : 0))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text("个书架")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 0.5, height: 36)

            VStack(spacing: 4) {
                Text("\(allBooks.count)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                Text("本书")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 0.5, height: 36)

            VStack(spacing: 4) {
                Text("\(uncategorizedBooks.count)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)
                Text("未分类")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.systemGray6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - 书架列表

    private var shelvesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("我的书架")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal)

            VStack(spacing: 10) {
                ForEach(bookshelves.filter { $0.name != "微信读书" }) { shelf in
                    let shelfBooks = allBooks.filter { $0.bookshelf?.persistentModelID == shelf.persistentModelID }
                    NavigationLink(destination: BookshelfDetailView(shelf: shelf)) {
                        ShelfCard(
                            name: shelf.name,
                            icon: shelf.icon,
                            bookCount: shelfBooks.count,
                            finishedCount: shelfBooks.filter { $0.status == .finished }.count
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            shelfToDelete = shelf
                            showDeleteAlert = true
                        } label: {
                            Label("删除书架", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 特殊入口

    private var specialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasWeRead || !uncategorizedBooks.isEmpty {
                Text("其他")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal)

                VStack(spacing: 10) {
                    if hasWeRead {
                        NavigationLink(destination: WeReadShelfDetailView()) {
                            ShelfCard(
                                name: "微信读书",
                                icon: "iphone",
                                bookCount: weReadBooks.count,
                                finishedCount: weReadBooks.filter { $0.status == .finished }.count
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !uncategorizedBooks.isEmpty {
                        NavigationLink(destination: UncategorizedBooksView()) {
                            ShelfCard(
                                name: "未分类",
                                icon: "tray",
                                bookCount: uncategorizedBooks.count,
                                finishedCount: uncategorizedBooks.filter { $0.status == .finished }.count
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func deleteShelf(withBooks: Bool) {
        guard let shelf = shelfToDelete else { return }
        if withBooks {
            if let books = shelf.books {
                for book in books {
                    modelContext.delete(book)
                }
            }
        } else {
            if let books = shelf.books {
                for book in books {
                    book.bookshelf = nil
                }
            }
        }
        modelContext.delete(shelf)
        try? modelContext.save()
        shelfToDelete = nil
    }
}

// MARK: - 书架卡片

struct ShelfCard: View {
    let name: String
    let icon: String
    let bookCount: Int
    let finishedCount: Int

    var body: some View {
        HStack(spacing: 14) {
            // 图标
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 44, height: 44)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    Text("\(bookCount) 本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if finishedCount > 0 {
                        Text("已读 \(finishedCount)")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        )
    }
}

// MARK: - 书架详情（真实书架）

struct BookshelfDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let shelf: Bookshelf
    @State private var showDeleteAlert = false
    @State private var bookForQuickTag: Book?
    @State private var bookForRating: Book?

    // 多选
    @State private var isSelecting = false
    @State private var selectedBooks: Set<PersistentIdentifier> = []
    @State private var showTagSheet = false
    @State private var showMoveSheet = false
    @State private var showStatusSheet = false
    @State private var showRatingSheet = false

    private var books: [Book] {
        (shelf.books ?? []).sorted { $0.addedDate > $1.addedDate }
    }

    private var selectedBookObjects: [Book] {
        books.filter { selectedBooks.contains($0.persistentModelID) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(books) { book in
                    if isSelecting {
                        shelfSelectableRow(book: book)
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

            if isSelecting && !selectedBooks.isEmpty {
                shelfBatchBar
            }
        }
        .navigationTitle(shelf.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isSelecting {
                    Button("取消") { exitSelectMode() }
                }
            }
            ToolbarItem(placement: .principal) {
                if isSelecting {
                    Text("已选 \(selectedBooks.count) 本")
                        .font(.headline)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSelecting {
                    Button(selectedBooks.count == books.count ? "取消全选" : "全选") {
                        if selectedBooks.count == books.count {
                            selectedBooks.removeAll()
                        } else {
                            selectedBooks = Set(books.map(\.persistentModelID))
                        }
                    }
                } else {
                    Menu {
                        Button("选择") { isSelecting = true }
                        Divider()
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("删除书架", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("删除书架", isPresented: $showDeleteAlert) {
            Button("仅删除书架", role: .destructive) {
                deleteShelf(withBooks: false)
            }
            Button("连同图书一起删除", role: .destructive) {
                deleteShelf(withBooks: true)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("书架「\(shelf.name)」中有 \(books.count) 本书。\n要一起删除这些图书吗？")
        }
        .sheet(item: $bookForQuickTag) { book in
            QuickTagView(book: book)
        }
        .sheet(item: $bookForRating) { book in
            MarkReadRatingView(book: book)
        }
        .sheet(isPresented: $showTagSheet) {
            BatchTagView(books: selectedBookObjects) { exitSelectMode() }
        }
        .sheet(isPresented: $showMoveSheet) {
            BatchMoveShelfView(books: selectedBookObjects) { exitSelectMode() }
        }
        .sheet(isPresented: $showStatusSheet) {
            BatchStatusView(books: selectedBookObjects) { exitSelectMode() }
        }
        .sheet(isPresented: $showRatingSheet) {
            BatchRatingView(books: selectedBookObjects) { exitSelectMode() }
        }
        .overlay {
            if books.isEmpty && !isSelecting {
                ContentUnavailableView(
                    "书架是空的",
                    systemImage: "books.vertical",
                    description: Text("从藏书中将图书添加到此书架")
                )
            }
        }
    }

    private func shelfSelectableRow(book: Book) -> some View {
        let isSelected = selectedBooks.contains(book.persistentModelID)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .orange : .secondary)
            BookRowView(book: book)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedBooks.remove(book.persistentModelID)
            } else {
                selectedBooks.insert(book.persistentModelID)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private var shelfBatchBar: some View {
        HStack(spacing: 0) {
            shelfBatchBtn(icon: "tag", label: "标签") { showTagSheet = true }
            shelfBatchBtn(icon: "arrow.right.square", label: "移动") { showMoveSheet = true }
            shelfBatchBtn(icon: "book", label: "状态") { showStatusSheet = true }
            shelfBatchBtn(icon: "star", label: "评分") { showRatingSheet = true }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Divider() }
    }

    private func shelfBatchBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.orange)
        }
    }

    private func exitSelectMode() {
        isSelecting = false
        selectedBooks.removeAll()
    }

    private func deleteShelf(withBooks: Bool) {
        if withBooks {
            for book in books {
                modelContext.delete(book)
            }
        } else {
            for book in books {
                book.bookshelf = nil
            }
        }
        modelContext.delete(shelf)
        try? modelContext.save()
    }
}

// MARK: - 微信读书虚拟书架详情

struct WeReadShelfDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBooks: [Book]
    @State private var bookForQuickTag: Book?
    @State private var bookForRating: Book?
    @State private var isSelecting = false
    @State private var selectedBooks: Set<PersistentIdentifier> = []
    @State private var showTagSheet = false
    @State private var showMoveSheet = false
    @State private var showStatusSheet = false
    @State private var showRatingSheet = false

    private var weReadBooks: [Book] {
        allBooks.filter { book in
            book.tags?.contains(where: { $0.name == "微信读书" }) == true
        }.sorted { $0.addedDate > $1.addedDate }
    }

    private var selectedBookObjects: [Book] {
        weReadBooks.filter { selectedBooks.contains($0.persistentModelID) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(weReadBooks) { book in
                    if isSelecting {
                        wereadSelectableRow(book: book)
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

            if isSelecting && !selectedBooks.isEmpty {
                HStack(spacing: 0) {
                    wrBatchBtn(icon: "tag", label: "标签") { showTagSheet = true }
                    wrBatchBtn(icon: "arrow.right.square", label: "移动") { showMoveSheet = true }
                    wrBatchBtn(icon: "book", label: "状态") { showStatusSheet = true }
                    wrBatchBtn(icon: "star", label: "评分") { showRatingSheet = true }
                }
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .overlay(alignment: .top) { Divider() }
            }
        }
        .navigationTitle("微信读书")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isSelecting {
                    Button("取消") { isSelecting = false; selectedBooks.removeAll() }
                }
            }
            ToolbarItem(placement: .principal) {
                if isSelecting {
                    Text("已选 \(selectedBooks.count) 本").font(.headline)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSelecting {
                    Button(selectedBooks.count == weReadBooks.count ? "取消全选" : "全选") {
                        if selectedBooks.count == weReadBooks.count {
                            selectedBooks.removeAll()
                        } else {
                            selectedBooks = Set(weReadBooks.map(\.persistentModelID))
                        }
                    }
                }
            }
        }
        .sheet(item: $bookForQuickTag) { book in
            QuickTagView(book: book)
        }
        .sheet(item: $bookForRating) { book in
            MarkReadRatingView(book: book)
        }
        .sheet(isPresented: $showTagSheet) {
            BatchTagView(books: selectedBookObjects) { isSelecting = false; selectedBooks.removeAll() }
        }
        .sheet(isPresented: $showMoveSheet) {
            BatchMoveShelfView(books: selectedBookObjects) { isSelecting = false; selectedBooks.removeAll() }
        }
        .sheet(isPresented: $showStatusSheet) {
            BatchStatusView(books: selectedBookObjects) { isSelecting = false; selectedBooks.removeAll() }
        }
        .sheet(isPresented: $showRatingSheet) {
            BatchRatingView(books: selectedBookObjects) { isSelecting = false; selectedBooks.removeAll() }
        }
        .overlay {
            if weReadBooks.isEmpty {
                ContentUnavailableView(
                    "没有微信读书图书",
                    systemImage: "iphone",
                    description: Text("从微信读书导入的书会显示在这里")
                )
            }
        }
    }

    private func wereadSelectableRow(book: Book) -> some View {
        let isSelected = selectedBooks.contains(book.persistentModelID)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .orange : .secondary)
            BookRowView(book: book)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { selectedBooks.remove(book.persistentModelID) }
            else { selectedBooks.insert(book.persistentModelID) }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private func wrBatchBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.orange)
        }
    }
}

// MARK: - 未分类书籍

struct UncategorizedBooksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBooks: [Book]
    @State private var bookForQuickTag: Book?
    @State private var bookForRating: Book?
    @State private var isSelecting = false
    @State private var selectedBooks: Set<PersistentIdentifier> = []
    @State private var showTagSheet = false
    @State private var showMoveSheet = false
    @State private var showStatusSheet = false
    @State private var showRatingSheet = false

    private var uncategorizedBooks: [Book] {
        allBooks.filter { $0.bookshelf == nil && !$0.isArchived && $0.wereadBookId == nil }
            .sorted { $0.addedDate > $1.addedDate }
    }

    private var selectedBookObjects: [Book] {
        uncategorizedBooks.filter { selectedBooks.contains($0.persistentModelID) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(uncategorizedBooks) { book in
                    if isSelecting {
                        uncatSelectableRow(book: book)
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

            if isSelecting && !selectedBooks.isEmpty {
                HStack(spacing: 0) {
                    uncatBatchBtn(icon: "tag", label: "标签") { showTagSheet = true }
                    uncatBatchBtn(icon: "arrow.right.square", label: "移动") { showMoveSheet = true }
                    uncatBatchBtn(icon: "book", label: "状态") { showStatusSheet = true }
                    uncatBatchBtn(icon: "star", label: "评分") { showRatingSheet = true }
                }
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .overlay(alignment: .top) { Divider() }
            }
        }
        .navigationTitle("未分类")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isSelecting {
                    Button("取消") { isSelecting = false; selectedBooks.removeAll() }
                }
            }
            ToolbarItem(placement: .principal) {
                if isSelecting {
                    Text("已选 \(selectedBooks.count) 本").font(.headline)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSelecting {
                    Button(selectedBooks.count == uncategorizedBooks.count ? "取消全选" : "全选") {
                        if selectedBooks.count == uncategorizedBooks.count {
                            selectedBooks.removeAll()
                        } else {
                            selectedBooks = Set(uncategorizedBooks.map(\.persistentModelID))
                        }
                    }
                }
            }
        }
        .sheet(item: $bookForQuickTag) { book in
            QuickTagView(book: book)
        }
        .sheet(item: $bookForRating) { book in
            MarkReadRatingView(book: book)
        }
        .sheet(isPresented: $showTagSheet) {
            BatchTagView(books: selectedBookObjects) { isSelecting = false; selectedBooks.removeAll() }
        }
        .sheet(isPresented: $showMoveSheet) {
            BatchMoveShelfView(books: selectedBookObjects) { isSelecting = false; selectedBooks.removeAll() }
        }
        .sheet(isPresented: $showStatusSheet) {
            BatchStatusView(books: selectedBookObjects) { isSelecting = false; selectedBooks.removeAll() }
        }
        .sheet(isPresented: $showRatingSheet) {
            BatchRatingView(books: selectedBookObjects) { isSelecting = false; selectedBooks.removeAll() }
        }
        .overlay {
            if uncategorizedBooks.isEmpty {
                ContentUnavailableView(
                    "没有未分类图书",
                    systemImage: "tray",
                    description: Text("所有图书都已归入书架")
                )
            }
        }
    }

    private func uncatSelectableRow(book: Book) -> some View {
        let isSelected = selectedBooks.contains(book.persistentModelID)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? .orange : .secondary)
            BookRowView(book: book)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { selectedBooks.remove(book.persistentModelID) }
            else { selectedBooks.insert(book.persistentModelID) }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private func uncatBatchBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.orange)
        }
    }
}

// MARK: - 新增书架

struct AddBookshelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedIcon = "books.vertical"

    private let iconOptions = [
        "books.vertical", "book.closed", "book",
        "text.book.closed", "magazine", "newspaper",
        "graduationcap", "brain.head.profile", "lightbulb",
        "star", "heart", "bookmark"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("书架名称") {
                    TextField("输入书架名称", text: $name)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundStyle(selectedIcon == icon ? .orange : .secondary)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        selectedIcon == icon ?
                                        Color.orange.opacity(0.1) : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("新建书架")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        createBookshelf()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func createBookshelf() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let shelf = Bookshelf(name: trimmed, icon: selectedIcon)
        modelContext.insert(shelf)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    BookshelfListView()
        .modelContainer(for: [Book.self, Bookshelf.self, Tag.self], inMemory: true)
}
