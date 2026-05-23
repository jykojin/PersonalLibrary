import SwiftUI
import SwiftData

/// 高级搜索 — 组合多个条件筛选图书
struct AdvancedSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.addedDate, order: .reverse) private var allBooks: [Book]
    @Query(sort: \Bookshelf.name) private var bookshelves: [Bookshelf]
    @Query private var allTags: [Tag]

    /// 搜索结果回调：传回匹配的书籍，关闭搜索页回到藏书页展示
    var onSearchResults: (([Book]) -> Void)?

    // 文本条件
    @State private var titleQuery = ""
    @State private var authorQuery = ""
    @State private var publisherQuery = ""
    @State private var isbnQuery = ""
    @State private var translatorQuery = ""

    // 筛选条件
    @State private var selectedBookType: BookType?
    @State private var selectedStatus: ReadingStatus?
    @State private var selectedShelf: Bookshelf?
    @State private var selectedTag: Tag?
    @State private var filterNoShelf = false

    // 评分条件
    @State private var ratingFilter: RatingFilter = .any
    @State private var minRating: Int = 1
    @State private var maxRating: Int = 5

    enum RatingFilter: String, CaseIterable {
        case any = "不限"
        case hasRating = "有评分"
        case noRating = "未评分"
        case exact = "指定星数"
        case range = "分数区间"
    }

    // 特殊条件
    @State private var missingAuthor = false
    @State private var missingPublisher = false
    @State private var missingPrice = false
    @State private var missingPages = false
    @State private var missingISBN = false
    @State private var missingCover = false
    @State private var missingDescription = false
    @State private var missingAuthorDesc = false
    @State private var showArchived = false
    @State private var addedAfter: Date?
    @State private var addedBefore: Date?
    @State private var showAddedAfterPicker = false
    @State private var showAddedBeforePicker = false

    // 搜索结果
    @State private var hasSearched = false

    private var results: [Book] {
        guard hasSearched else { return [] }

        return allBooks.filter { book in
            // 归档过滤：默认只显示未归档，开启 showArchived 则只显示已归档
            if showArchived {
                if !book.isArchived { return false }
            } else {
                if book.isArchived { return false }
            }

            // 文本条件（非空才参与过滤）
            if !titleQuery.isEmpty &&
               !book.title.localizedCaseInsensitiveContains(titleQuery) {
                return false
            }
            if !authorQuery.isEmpty &&
               !book.author.localizedCaseInsensitiveContains(authorQuery) {
                return false
            }
            if !publisherQuery.isEmpty &&
               !(book.publisher?.localizedCaseInsensitiveContains(publisherQuery) == true) {
                return false
            }
            if !isbnQuery.isEmpty &&
               !(book.isbn?.localizedCaseInsensitiveContains(isbnQuery) == true) {
                return false
            }
            if !translatorQuery.isEmpty &&
               !(book.translator?.localizedCaseInsensitiveContains(translatorQuery) == true) {
                return false
            }

            // 书籍类型
            if let type = selectedBookType, book.bookType != type {
                return false
            }

            // 阅读状态
            if let status = selectedStatus, book.status != status {
                return false
            }

            // 书架
            if let shelf = selectedShelf, book.bookshelf?.persistentModelID != shelf.persistentModelID {
                return false
            }

            // 无书架
            if filterNoShelf && book.bookshelf != nil {
                return false
            }

            // 标签
            if let tag = selectedTag {
                if !(book.tags?.contains(where: { $0.persistentModelID == tag.persistentModelID }) == true) {
                    return false
                }
            }

            // 缺作者
            if missingAuthor {
                let author = book.author.trimmingCharacters(in: .whitespaces)
                if !author.isEmpty && author != "未知作者" {
                    return false
                }
            }

            // 缺出版社
            if missingPublisher {
                if let p = book.publisher, !p.trimmingCharacters(in: .whitespaces).isEmpty {
                    return false
                }
            }

            // 缺价格
            if missingPrice {
                if let p = book.price, !p.trimmingCharacters(in: .whitespaces).isEmpty {
                    return false
                }
            }

            // 缺页数
            if missingPages {
                if book.totalPages > 0 { return false }
            }

            // 缺ISBN
            if missingISBN {
                if let isbn = book.isbn, !isbn.trimmingCharacters(in: .whitespaces).isEmpty {
                    return false
                }
            }

            // 缺封面
            if missingCover {
                if book.coverImageData != nil { return false }
            }

            // 缺内容简介
            if missingDescription {
                if let d = book.bookDescription, !d.trimmingCharacters(in: .whitespaces).isEmpty {
                    return false
                }
            }

            // 缺作者简介
            if missingAuthorDesc {
                if let d = book.authorDescription, !d.trimmingCharacters(in: .whitespaces).isEmpty {
                    return false
                }
            }

            // 评分筛选
            switch ratingFilter {
            case .any:
                break
            case .hasRating:
                if book.rating == nil { return false }
            case .noRating:
                if book.rating != nil { return false }
            case .exact:
                if book.rating != minRating { return false }
            case .range:
                guard let r = book.rating else { return false }
                if r < minRating || r > maxRating { return false }
            }

            // 加入时间范围
            if let after = addedAfter, book.addedDate < after {
                return false
            }
            if let before = addedBefore, book.addedDate > before {
                return false
            }

            return true
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // 文本搜索条件
                textConditionsSection

                // 筛选条件
                filterConditionsSection

                // 特殊条件
                specialConditionsSection

                // 搜索结果
                if hasSearched {
                    resultsSection
                }
            }
            .navigationTitle("高级搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("搜索") {
                        hasSearched = true
                        if let callback = onSearchResults {
                            callback(results)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - 文本条件

    private var textConditionsSection: some View {
        Section("文本条件") {
            AdvancedSearchField(label: "书名", icon: "book", text: $titleQuery)
            AdvancedSearchField(label: "作者", icon: "person", text: $authorQuery)
            AdvancedSearchField(label: "出版社", icon: "building.2", text: $publisherQuery)
            AdvancedSearchField(label: "ISBN", icon: "barcode", text: $isbnQuery)
            AdvancedSearchField(label: "译者", icon: "person.2", text: $translatorQuery)
        }
    }

    // MARK: - 筛选条件

    private var filterConditionsSection: some View {
        Section("筛选条件") {
            // 书籍类型
            HStack {
                Label("书籍类型", systemImage: "doc.plaintext")
                Spacer()
                Picker("", selection: $selectedBookType) {
                    Text("不限").tag(nil as BookType?)
                    ForEach(BookType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type as BookType?)
                    }
                }
                .pickerStyle(.menu)
            }

            // 阅读状态
            HStack {
                Label("阅读状态", systemImage: "bookmark")
                Spacer()
                Picker("", selection: $selectedStatus) {
                    Text("不限").tag(nil as ReadingStatus?)
                    ForEach(ReadingStatus.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status as ReadingStatus?)
                    }
                }
                .pickerStyle(.menu)
            }

            // 书架
            HStack {
                Label("所在书架", systemImage: "square.stack.3d.up")
                Spacer()
                Picker("", selection: $selectedShelf) {
                    Text("不限").tag(nil as Bookshelf?)
                    ForEach(bookshelves) { shelf in
                        Text(shelf.name).tag(shelf as Bookshelf?)
                    }
                }
                .pickerStyle(.menu)
            }

            // 标签
            HStack {
                Label("包含标签", systemImage: "tag")
                Spacer()
                Picker("", selection: $selectedTag) {
                    Text("不限").tag(nil as Tag?)
                    ForEach(allTags) { tag in
                        Text(tag.name).tag(tag as Tag?)
                    }
                }
                .pickerStyle(.menu)
            }

            // 评分
            HStack {
                Label("评分", systemImage: "star")
                Spacer()
                Picker("", selection: $ratingFilter) {
                    ForEach(RatingFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            if ratingFilter == .exact {
                HStack {
                    Text("星数")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            minRating = star
                        } label: {
                            Image(systemName: star <= minRating ? "star.fill" : "star")
                                .foregroundStyle(star <= minRating ? .yellow : .gray)
                        }
                    }
                }
            }

            if ratingFilter == .range {
                HStack {
                    Text("最低")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $minRating) {
                        ForEach(1...5, id: \.self) { Text("\($0) 星").tag($0) }
                    }
                    .pickerStyle(.menu)
                    Text("~")
                    Text("最高")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $maxRating) {
                        ForEach(1...5, id: \.self) { Text("\($0) 星").tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    // MARK: - 特殊条件

    private var specialConditionsSection: some View {
        Section("特殊条件") {
            Toggle(isOn: $showArchived) {
                Label("已取消收藏的书", systemImage: "heart.slash")
            }

            Toggle(isOn: $missingAuthor) {
                Label("缺少作者信息", systemImage: "person.slash")
            }

            Toggle(isOn: $missingPublisher) {
                Label("缺少出版社", systemImage: "building.2")
            }

            Toggle(isOn: $missingPrice) {
                Label("缺少价格", systemImage: "yensign.circle")
            }

            Toggle(isOn: $missingPages) {
                Label("缺少页数", systemImage: "doc")
            }

            Toggle(isOn: $missingISBN) {
                Label("缺少ISBN", systemImage: "barcode")
            }

            Toggle(isOn: $missingCover) {
                Label("缺少封面", systemImage: "photo")
            }

            Toggle(isOn: $missingDescription) {
                Label("缺少内容简介", systemImage: "text.alignleft")
            }

            Toggle(isOn: $missingAuthorDesc) {
                Label("缺少作者简介", systemImage: "person.text.rectangle")
            }

            Toggle(isOn: $filterNoShelf) {
                Label("未归入书架", systemImage: "tray")
            }

            // 加入时间 - 起始
            HStack {
                Label("加入时间从", systemImage: "calendar")
                Spacer()
                if let date = addedAfter {
                    Text(date, style: .date)
                        .foregroundStyle(.orange)
                    Button {
                        addedAfter = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } else {
                    Button("选择") {
                        showAddedAfterPicker = true
                    }
                    .foregroundStyle(.orange)
                }
            }
            .sheet(isPresented: $showAddedAfterPicker) {
                AdvancedSearchDatePicker(title: "加入时间从", date: $addedAfter)
            }

            // 加入时间 - 截止
            HStack {
                Label("加入时间到", systemImage: "calendar.badge.clock")
                Spacer()
                if let date = addedBefore {
                    Text(date, style: .date)
                        .foregroundStyle(.orange)
                    Button {
                        addedBefore = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } else {
                    Button("选择") {
                        showAddedBeforePicker = true
                    }
                    .foregroundStyle(.orange)
                }
            }
            .sheet(isPresented: $showAddedBeforePicker) {
                AdvancedSearchDatePicker(title: "加入时间到", date: $addedBefore)
            }
        }
    }

    // MARK: - 搜索结果

    private var resultsSection: some View {
        Section("搜索结果（\(results.count) 本）") {
            if results.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("没有匹配的图书")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                ForEach(results) { book in
                    if showArchived {
                        HStack {
                            BookRowView(book: book)
                            Spacer()
                            Button {
                                book.isArchived = false
                                try? modelContext.save()
                                hasSearched = true  // 刷新结果
                            } label: {
                                Text("恢复收藏")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                        }
                    } else {
                        NavigationLink(destination: BookDetailView(book: book)) {
                            BookRowView(book: book)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - 搜索输入行

private struct AdvancedSearchField: View {
    let label: String
    let icon: String
    @Binding var text: String

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .frame(width: 90, alignment: .leading)
            TextField("输入\(label)", text: $text)
                .font(.subheadline)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - 日期选择器 Sheet

private struct AdvancedSearchDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var date: Date?
    @State private var pickedDate = Date()

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    title,
                    selection: $pickedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()

                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        date = pickedDate
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    AdvancedSearchView()
        .modelContainer(for: [Book.self, Bookshelf.self, Tag.self], inMemory: true)
}
