import SwiftUI
import SwiftData
import PhotosUI

/// 编辑书籍信息 — 支持编辑所有字段，封面可从相册/相机/网络搜索获取
struct EditBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var book: Book
    @Query(sort: \Bookshelf.sortOrder) private var bookshelves: [Bookshelf]
    @Query private var allTags: [Tag]

    // 基本信息
    @State private var title: String = ""
    @State private var author: String = ""
    @State private var translator: String = ""
    @State private var publisher: String = ""
    @State private var isbn: String = ""
    @State private var price: String = ""
    @State private var totalPages: String = ""
    @State private var publishDate: Date?
    @State private var showDatePicker = false
    @State private var doubanURL: String = ""

    // 类型与状态
    @State private var bookType: BookType = .paper
    @State private var status: ReadingStatus = .idle
    @State private var rating: Int = 0

    // 描述
    @State private var bookDescription: String = ""
    @State private var authorDescription: String = ""
    @State private var notes: String = ""

    // 书架与标签
    @State private var selectedShelf: Bookshelf?
    @State private var selectedTags: Set<String> = []
    @State private var newTagName: String = ""

    // 封面
    @State private var coverData: Data?
    @State private var showCamera = false
    @State private var showWebSearch = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    // 智能补全
    @State private var isAutoFilling = false
    @State private var autoFillMessage: String = ""
    @State private var showFillResult = false
    @State private var fillResult: SmartFillResult?

    var body: some View {
        NavigationStack {
            Form {
                smartFillSection
                coverSection
                basicInfoSection
                typeAndStatusSection
                descriptionSection
                shelfAndTagsSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("编辑图书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveChanges() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadBookData() }
            .sheet(isPresented: $showWebSearch) {
                CoverWebSearchView(bookTitle: title, bookAuthor: author) { imageData in
                    coverData = imageData
                }
            }
            .sheet(isPresented: $showDatePicker) {
                EditBookDatePicker(title: "出版日期", date: $publishDate)
            }
        }
    }

    // MARK: - 封面

    private var coverSection: some View {
        Section("封面") {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    if let data = coverData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 110, height: 160)
                            .overlay {
                                Image(systemName: "book.closed")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                    }

                    HStack(spacing: 16) {
                        // 相册
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("相册", systemImage: "photo")
                                .font(.caption)
                        }
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                    coverData = data
                                }
                            }
                        }

                        // 相机
                        Button {
                            showCamera = true
                        } label: {
                            Label("拍照", systemImage: "camera")
                                .font(.caption)
                        }

                        // 网络搜索
                        Button {
                            showWebSearch = true
                        } label: {
                            Label("搜索", systemImage: "magnifyingglass")
                                .font(.caption)
                        }

                        // 清除
                        if coverData != nil {
                            Button(role: .destructive) {
                                coverData = nil
                            } label: {
                                Label("清除", systemImage: "xmark")
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { imageData in
                    coverData = imageData
                }
            }
        }
    }

    // MARK: - 基本信息

    private var basicInfoSection: some View {
        Section("基本信息") {
            EditLabeledField(label: "书名", text: $title, required: true)
            EditLabeledField(label: "作者", text: $author)
            EditLabeledField(label: "译者", text: $translator)
            EditLabeledField(label: "出版社", text: $publisher)
            EditLabeledField(label: "ISBN", text: $isbn)
            EditLabeledField(label: "定价", text: $price)
            EditLabeledField(label: "总页数", text: $totalPages)
                .keyboardType(.numberPad)

            // 出版日期
            HStack {
                Text("出版日期")
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                Spacer()
                if let date = publishDate {
                    Text(date, format: .dateTime.year().month())
                        .foregroundStyle(.primary)
                    Button {
                        publishDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } else {
                    Button("选择") {
                        showDatePicker = true
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - 类型与状态

    private var typeAndStatusSection: some View {
        Section("类型与状态") {
            Picker("书籍类型", selection: $bookType) {
                ForEach(BookType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            Picker("阅读状态", selection: $status) {
                ForEach(ReadingStatus.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }

            // 开始阅读时间
            if let startDate = book.startedReadingDate {
                HStack {
                    Text("开始阅读")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(startDate, format: .dateTime.year().month().day())
                        .foregroundStyle(.primary)
                }
            }

            // 读完时间
            if let finishDate = book.finishedDate {
                HStack {
                    Text("读完时间")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(finishDate, format: .dateTime.year().month().day())
                        .foregroundStyle(.primary)
                }
            }

            // 微信读书阅读时长
            if book.wereadReadingHours > 0 {
                HStack {
                    Text("阅读时长")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f 小时", book.wereadReadingHours))
                        .foregroundStyle(.primary)
                }
            }

            // 评分
            HStack {
                Text("评分")
                Spacer()
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(star <= rating ? .yellow : .gray.opacity(0.3))
                            .onTapGesture {
                                if rating == star {
                                    rating = 0  // 再次点击清除
                                } else {
                                    rating = star
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: - 描述

    private var descriptionSection: some View {
        Section("描述") {
            VStack(alignment: .leading, spacing: 4) {
                Text("书籍简介")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $bookDescription)
                    .frame(minHeight: 80)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("作者简介")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $authorDescription)
                    .frame(minHeight: 60)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("备注")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .frame(minHeight: 60)
            }
        }
    }

    // MARK: - 书架与标签

    private var shelfAndTagsSection: some View {
        Section("书架与标签") {
            // 书架
            Picker("书架", selection: $selectedShelf) {
                Text("无").tag(nil as Bookshelf?)
                ForEach(bookshelves) { shelf in
                    Text(shelf.name).tag(shelf as Bookshelf?)
                }
            }

            // 已选标签
            if !selectedTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(selectedTags).sorted(), id: \.self) { tagName in
                        HStack(spacing: 2) {
                            Text(tagName)
                                .font(.caption)
                            Button {
                                selectedTags.remove(tagName)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                    }
                }
            }

            // 添加标签
            HStack {
                TextField("添加标签", text: $newTagName)
                    .font(.subheadline)
                Button("添加") {
                    let trimmed = newTagName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        selectedTags.insert(trimmed)
                        newTagName = ""
                    }
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // 已有标签快捷选择
            if !allTags.isEmpty {
                DisclosureGroup("从已有标签选择") {
                    FlowLayout(spacing: 6) {
                        ForEach(allTags) { tag in
                            let isSelected = selectedTags.contains(tag.name)
                            Text(tag.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isSelected ? Color.orange.opacity(0.15) : Color(.systemGray6))
                                .foregroundStyle(isSelected ? .orange : .secondary)
                                .clipShape(Capsule())
                                .onTapGesture {
                                    if isSelected {
                                        selectedTags.remove(tag.name)
                                    } else {
                                        selectedTags.insert(tag.name)
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 数据加载与保存

    private func loadBookData() {
        title = book.title
        author = book.author
        translator = book.translator ?? ""
        publisher = book.publisher ?? ""
        isbn = book.isbn ?? ""
        price = book.price ?? ""
        totalPages = book.totalPages > 0 ? String(book.totalPages) : ""
        publishDate = book.publishDate
        doubanURL = book.doubanURL ?? ""
        bookType = book.bookType
        status = book.status
        rating = book.rating ?? 0
        bookDescription = book.bookDescription ?? ""
        authorDescription = book.authorDescription ?? ""
        notes = book.notes ?? ""
        selectedShelf = book.bookshelf
        selectedTags = Set((book.tags ?? []).map(\.name))
        coverData = book.coverImageData

        // 如果没有有效封面数据（nil 或空 Data），先查内存缓存，再走网络
        if coverData == nil || coverData!.isEmpty {
            Task {
                // 1. 内存缓存（列表已下载过的封面在这里）
                let cacheKey = "\(book.title)|\(book.author)"
                if let cached = CoverImageCache.shared.image(for: cacheKey),
                   let data = cached.jpegData(compressionQuality: 0.85) {
                    coverData = data
                    return
                }

                // 2. 完整网络 pipeline
                let data = await CoverFetchService.shared.fetchCoverThrottled(
                    coverImageURL: book.coverImageURL,
                    isbn: book.isbn,
                    doubanURL: book.doubanURL,
                    title: book.title,
                    author: book.author
                )
                if let data {
                    coverData = data
                }
            }
        }
    }

    // MARK: - 智能补全

    private var smartFillSection: some View {
        Section {
            if isAutoFilling {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(autoFillMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let result = fillResult {
                // 显示补全结果
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: result.hasAnyFill ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(result.hasAnyFill ? .green : .orange)
                        Text(result.hasAnyFill ? "已补全部分信息" : "未找到可补全的信息")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    // 各源状态
                    ForEach(Array(result.sourceStatuses.enumerated()), id: \.offset) { _, source in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor(source.status))
                                .frame(width: 6, height: 6)
                            Text(source.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(source.status.displayText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                // 初始状态 — 显示按钮
                Button {
                    Task { await performSmartFill() }
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("智能补全缺失信息")
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty && isbn.isEmpty)
            }
        } header: {
            Text("数据补全")
        } footer: {
            if fillResult == nil && !isAutoFilling {
                if book.wereadBookId != nil {
                    Text("从微信读书补全：出版社、简介、阅读时长等")
                        .font(.caption2)
                } else {
                    Text("从豆瓣、Open Library、Google Books 查找：出版社、页数、作者、图书简介、作者简介")
                        .font(.caption2)
                }
            }
        }
    }

    private func statusColor(_ status: LookupSourceStatus) -> Color {
        switch status {
        case .found: return .green
        case .notFound: return .red
        case .notAttempted: return .gray
        case .error: return .orange
        }
    }

    private func performSmartFill() async {
        isAutoFilling = true
        autoFillMessage = "正在查询数据源..."
        defer { isAutoFilling = false }

        // 微信读书电纸书：先从微信读书补全
        let wereadId = book.wereadBookId
        if let wereadId, !wereadId.isEmpty {
            await fillFromWeRead(bookId: wereadId)

            // 本地作者简介
            if authorDescription.isEmpty && !author.isEmpty && author != "未知作者" {
                autoFillMessage = "正在从本地书库查找作者简介..."
                if let localDesc = findLocalAuthorDescription(for: author) {
                    authorDescription = localDesc
                }
            }

            // 微信读书缺描述时，是否查外部源：
            // - 用户导入书（isWereadUserImported=true）：可以搜外部源补全
            // - 平台书（isWereadUserImported=false）：不搜外部源，只用微信读书+本地
            var externalFilled = false
            AppLogger.warning("performSmartFill: bookDesc.isEmpty=\(bookDescription.isEmpty), authorDesc.isEmpty=\(authorDescription.isEmpty), isbn=\(isbn), title=\(title), author=\(author), isUserImported=\(book.isWereadUserImported)", category: "EditBook")
            let shouldSearchExternal = book.isWereadUserImported && (bookDescription.isEmpty || authorDescription.isEmpty)
            if shouldSearchExternal {
                autoFillMessage = "正在从外部数据源补全描述..."
                AppLogger.warning("performSmartFill: calling ISBNLookupService.smartFill for external sources...", category: "EditBook")
                let service = ISBNLookupService()
                let extResult = await service.smartFill(
                    isbn: isbn,
                    title: title,
                    author: author,
                    needsPublisher: false,
                    needsPages: false,
                    needsPrice: false,
                    needsPublishDate: false,
                    needsTranslator: false,
                    needsAuthor: false,
                    needsBookDesc: bookDescription.isEmpty,
                    needsAuthorDesc: authorDescription.isEmpty
                )
                AppLogger.warning("performSmartFill: external result bookDesc=\(extResult.bookDescription != nil), authorDesc=\(extResult.authorDescription != nil)", category: "EditBook")
                if let d = extResult.bookDescription { bookDescription = d; externalFilled = true }
                if let d = extResult.authorDescription { authorDescription = d; externalFilled = true }
            } else {
                AppLogger.warning("performSmartFill: skipped external sources (platform book or both descriptions non-empty)", category: "EditBook")
            }

            // 构建结果
            var statuses: [(name: String, status: LookupSourceStatus)] = []
            statuses.append(("微信读书", book.wereadEnrichedDate != nil ? .found : .notFound))
            if !authorDescription.isEmpty {
                statuses.append(("本地书库", .found))
            }
            if externalFilled {
                statuses.append(("外部数据源", .found))
            }
            fillResult = SmartFillResult(sourceStatuses: statuses)
            return
        }

        // 非微信读书的书：走 ISBN 外部源
        var needsAuthorDesc = authorDescription.isEmpty

        // 优先从本地数据库查找同名作者的简介
        if needsAuthorDesc && !author.isEmpty && author != "未知作者" {
            autoFillMessage = "正在从本地书库查找作者简介..."
            if let localDesc = findLocalAuthorDescription(for: author) {
                authorDescription = localDesc
                needsAuthorDesc = false
            }
        }

        let service = ISBNLookupService()
        let result = await service.smartFill(
            isbn: isbn,
            title: title,
            author: author,
            needsPublisher: publisher.isEmpty,
            needsPages: totalPages.isEmpty,
            needsPrice: price.isEmpty,
            needsPublishDate: publishDate == nil,
            needsTranslator: translator.isEmpty,
            needsAuthor: author.isEmpty || author == "未知作者",
            needsBookDesc: bookDescription.isEmpty,
            needsAuthorDesc: needsAuthorDesc
        )

        // 填充到表单
        if let p = result.publisher { publisher = p }
        if let p = result.totalPages { totalPages = String(p) }
        if let p = result.price { price = p }
        if let d = result.publishDate { publishDate = parsePublishDateString(d) }
        if let t = result.translator { translator = t }
        if let a = result.author { author = a }
        if let d = result.bookDescription { bookDescription = d }
        if let d = result.authorDescription { authorDescription = d }

        fillResult = result
    }

    /// 从微信读书 API 补全书籍信息 + 阅读时长（使用统一 enrichBook 方法）
    private func fillFromWeRead(bookId: String) async {
        let mode = WeReadConnectionMode.current
        AppLogger.warning("fillFromWeRead START: bookId=\(bookId), mode=\(mode.rawValue)", category: "EditBook")

        let service: any WeReadDataSource = mode == .skill
            ? WeReadSkillProvider()
            : WeReadService()
        let connected = await service.isConnected()
        AppLogger.warning("fillFromWeRead: connected=\(connected)", category: "EditBook")
        guard connected else {
            AppLogger.warning("fillFromWeRead: NOT connected, returning", category: "EditBook")
            return
        }

        autoFillMessage = "正在从微信读书补全..."

        // Step 1: enrichBook
        AppLogger.warning("fillFromWeRead: calling enrichBook...", category: "EditBook")
        do {
            let result = try await service.enrichBook(bookId: bookId)
            AppLogger.warning("fillFromWeRead: enrichBook OK, isUserImported=\(String(describing: result.isUserImported)), publisher=\(result.publisher ?? "nil"), isbn=\(result.isbn ?? "nil")", category: "EditBook")

            // 应用到表单字段（表单字段为 @State，不直接用 applyToBook）
            if publisher.isEmpty, let p = result.publisher, !p.isEmpty {
                publisher = p
            }
            if isbn.isEmpty, let i = result.isbn, !i.isEmpty {
                isbn = i
            }
            if bookDescription.isEmpty, let d = result.intro, !d.isEmpty {
                bookDescription = d
            }
            if price.isEmpty, let p = result.price, p > 0, p.isFinite {
                price = "¥\(String(format: "%.2f", p))"
            }
            if publishDate == nil, let pt = result.publishTime, !pt.isEmpty {
                publishDate = parsePublishDateString(pt)
            }
            if let type = result.bookType, type == .audiobook, bookType != .audiobook {
                bookType = .audiobook
            }
            // 用户导入标识：enrichBook 从 /book/info 获取
            if let imported = result.isUserImported, imported {
                book.isWereadUserImported = true
                AppLogger.warning("fillFromWeRead: set isWereadUserImported=true from enrichBook", category: "EditBook")
            }
            // 阅读时长（有不同就更新，防止0值覆盖）
            if abs(result.readingHours - book.wereadReadingHours) > 0.001 && result.readingHours > 0 {
                book.wereadReadingHours = result.readingHours
            }
            // 阅读进度（有不同就更新，防止0值覆盖）
            if result.progress != book.wereadProgress && result.progress > 0 {
                book.wereadProgress = result.progress
            }
            // 开始阅读时间（真实值覆盖，估算值填空或更新已有估算）
            if let st = result.startedReadingTime {
                if !result.isStartedReadingTimeEstimated {
                    book.startedReadingDate = st
                    book.isStartedReadingDateEstimated = false
                } else if book.startedReadingDate == nil || book.isStartedReadingDateEstimated {
                    book.startedReadingDate = st
                    book.isStartedReadingDateEstimated = true
                }
            }
            // 完成时间（有不同就覆盖）
            if let ft = result.finishedTime, book.finishedDate != ft {
                book.finishedDate = ft
            }
            // 标记已补全
            book.wereadEnrichedDate = Date()
            try? modelContext.save()
        } catch is CancellationError {
            AppLogger.warning("fillFromWeRead: enrichBook CANCELLED (CancellationError)", category: "EditBook")
            return
        } catch {
            AppLogger.warning("fillFromWeRead: enrichBook FAILED: \(error)", category: "EditBook")
        }

        // Step 2: 如果 enrichBook 没能确定用户导入状态，用 bookId 前缀判断
        // CB_ 前缀是微信读书用户导入书籍的固定标识
        if !book.isWereadUserImported && bookId.hasPrefix("CB_") {
            book.isWereadUserImported = true
            try? modelContext.save()
            AppLogger.warning("fillFromWeRead: set isWereadUserImported=true from CB_ prefix", category: "EditBook")
        }

        // Step 3: 仍未确定时，从书架列表查找（兜底）
        if !book.isWereadUserImported {
            autoFillMessage = "正在确认书籍来源..."
            AppLogger.warning("fillFromWeRead: calling fetchAllBooks for type check...", category: "EditBook")
            do {
                let allBooks = try await service.fetchAllBooks()
                AppLogger.warning("fillFromWeRead: fetchAllBooks returned \(allBooks.count) items", category: "EditBook")
                if let item = allBooks.first(where: { $0.id == bookId }) {
                    AppLogger.warning("fillFromWeRead: found book in shelf, isUserImported=\(item.isUserImported)", category: "EditBook")
                    if item.isUserImported {
                        book.isWereadUserImported = true
                        try? modelContext.save()
                    }
                } else {
                    AppLogger.warning("fillFromWeRead: book NOT found in shelf by id=\(bookId)", category: "EditBook")
                }
            } catch is CancellationError {
                AppLogger.warning("fillFromWeRead: fetchAllBooks CANCELLED", category: "EditBook")
            } catch {
                AppLogger.warning("fillFromWeRead: fetchAllBooks FAILED: \(error)", category: "EditBook")
            }
        }
        AppLogger.warning("fillFromWeRead END, isWereadUserImported=\(book.isWereadUserImported)", category: "EditBook")
    }

    /// 解析出版日期字符串为 Date
    private func parsePublishDateString(_ dateString: String) -> Date? {
        for format in ["yyyy-MM-dd", "yyyy-MM", "yyyy"] {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: dateString) { return date }
        }
        return nil
    }

    /// 从本地数据库查找同名作者的最详细简介
    private func findLocalAuthorDescription(for authorName: String) -> String? {
        let descriptor = FetchDescriptor<Book>()
        guard let allBooks = try? modelContext.fetch(descriptor) else { return nil }

        let bestDesc = allBooks
            .filter { $0.author == authorName && $0.persistentModelID != book.persistentModelID }
            .compactMap { $0.authorDescription }
            .filter { !$0.isEmpty }
            .max(by: { $0.count < $1.count })

        return bestDesc
    }

    private func saveChanges() {
        book.title = title.trimmingCharacters(in: .whitespaces)
        book.author = author.trimmingCharacters(in: .whitespaces)
        book.translator = translator.isEmpty ? nil : translator
        book.publisher = publisher.isEmpty ? nil : publisher
        book.isbn = isbn.isEmpty ? nil : isbn
        book.price = price.isEmpty ? nil : price
        book.totalPages = Int(totalPages) ?? 0
        book.publishDate = publishDate
        book.doubanURL = doubanURL.isEmpty ? nil : doubanURL
        book.bookType = bookType
        if book.status != status {
            book.status = status
            book.statusChangedDate = Date()
        }
        book.rating = rating > 0 ? rating : nil
        book.bookDescription = bookDescription.isEmpty ? nil : bookDescription
        book.authorDescription = authorDescription.isEmpty ? nil : authorDescription
        book.notes = notes.isEmpty ? nil : notes
        book.bookshelf = selectedShelf
        // 只在封面数据真正变化时写入，避免不必要的大 blob I/O；相册选的大图先压成缩略图
        let newCover = coverData.map { CoverImageProcessor.thumbnailData(from: $0) }
        if book.coverImageData != newCover {
            book.coverImageData = newCover
        }

        if status == .finished && book.finishedDate == nil {
            book.finishedDate = Date()
        }

        // 更新标签
        var bookTags: [Tag] = []
        for tagName in selectedTags {
            if let existing = allTags.first(where: { $0.name == tagName }) {
                bookTags.append(existing)
            } else {
                let newTag = Tag(name: tagName)
                modelContext.insert(newTag)
                bookTags.append(newTag)
            }
        }
        book.tags = bookTags

        dismiss()
    }
}


// MARK: - 带标签的输入行

private struct EditLabeledField: View {
    let label: String
    @Binding var text: String
    var required: Bool = false

    var body: some View {
        HStack {
            HStack(spacing: 2) {
                Text(label)
                    .foregroundStyle(.secondary)
                if required {
                    Text("*")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .frame(width: 70, alignment: .leading)
            TextField(label, text: $text)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - 日期选择器

private struct EditBookDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var date: Date?
    @State private var pickedDate = Date()

    var body: some View {
        NavigationStack {
            DatePicker(
                title,
                selection: $pickedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
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

// MARK: - 相机拍照

struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data?) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (Data?) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image.jpegData(compressionQuality: 0.8))
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - 封面网络搜索

struct CoverWebSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let bookTitle: String
    let bookAuthor: String
    let onSelect: (Data) -> Void

    @State private var searchQuery: String = ""
    @State private var imageResults: [CoverSearchResult] = []
    @State private var isSearching = false
    @State private var selectedEngine: SearchEngine = .baidu
    @State private var currentPage = 1

    /// 分页上限（最多翻 5 页）
    private static let maxPages = 5
    /// 每页结果数（各引擎翻页偏移步进）
    private static let pageSize = 30

    enum SearchEngine: String, CaseIterable {
        case baidu = "百度"
        case bing = "Bing"
    }

    struct CoverSearchResult: Identifiable {
        let id = UUID()
        let thumbnailURL: String
        let fullURL: String
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索引擎选择
                Picker("搜索引擎", selection: $selectedEngine) {
                    ForEach(SearchEngine.allCases, id: \.self) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedEngine) { _, _ in
                    // 换引擎后若已有结果，重新从第 1 页搜索
                    if !imageResults.isEmpty || isSearching {
                        Task { await performSearch() }
                    }
                }

                // 搜索栏
                HStack {
                    TextField("搜索图书封面", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task { await performSearch() }
                        }
                    Button("搜索") {
                        Task { await performSearch() }
                    }
                    .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
                .padding(.horizontal)

                // 内容
                if imageResults.isEmpty && !isSearching {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("输入关键词搜索封面图片")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("建议搜索：书名 + 封面")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                } else if isSearching {
                    Spacer()
                    ProgressView("搜索中...")
                    Spacer()
                } else {
                    // 搜索结果网格
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(imageResults) { result in
                                AsyncImage(url: URL(string: result.thumbnailURL)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 140)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .onTapGesture {
                                                Task { await selectImage(result) }
                                            }
                                    case .failure:
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(.systemGray5))
                                            .frame(height: 140)
                                            .overlay {
                                                Image(systemName: "exclamationmark.triangle")
                                                    .foregroundStyle(.secondary)
                                            }
                                    default:
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(.systemGray6))
                                            .frame(height: 140)
                                            .overlay { ProgressView() }
                                    }
                                }
                            }
                        }
                        .padding()
                    }

                    // 分页条
                    paginationBar
                }
            }
            .navigationTitle("搜索封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if searchQuery.isEmpty {
                    searchQuery = "\(bookTitle) \(bookAuthor) 封面".trimmingCharacters(in: .whitespaces)
                }
            }
        }
    }

    // 分页条：上一页 / 页码 / 下一页（最多 5 页）
    private var paginationBar: some View {
        HStack(spacing: 24) {
            Button {
                Task { await goToPage(currentPage - 1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPage <= 1 || isSearching)

            Text("第 \(currentPage) / \(Self.maxPages) 页")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                Task { await goToPage(currentPage + 1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(currentPage >= Self.maxPages || isSearching)
        }
        .padding(.vertical, 8)
    }

    /// 从第 1 页开始搜索（新关键词 / 换引擎时调用）
    private func performSearch() async {
        await goToPage(1)
    }

    /// 跳到指定页（带边界保护）
    private func goToPage(_ page: Int) async {
        let target = max(1, min(page, Self.maxPages))
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isSearching = true
        currentPage = target
        imageResults = []

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let offset = (target - 1) * Self.pageSize

        switch selectedEngine {
        case .bing:
            await searchBing(encoded: encoded, offset: offset)
        case .baidu:
            await searchBaidu(encoded: encoded, offset: offset)
        }

        isSearching = false
    }

    private func searchBing(encoded: String, offset: Int) async {
        // first = 结果偏移量，用于翻页
        guard let url = URL(string: "https://www.bing.com/images/search?q=\(encoded)&form=HDRSC2&first=\(offset + 1)") else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return }

            // Bing 图片搜索将原图 URL 存在 murl 字段，缩略图在 turl
            var results: [CoverSearchResult] = []

            // 提取 murl（原图）
            let murlPattern = #"murl&quot;:&quot;(https?://[^&]+?)&quot;"#
            let turlPattern = #"turl&quot;:&quot;(https?://[^&]+?)&quot;"#

            let murls = extractMatches(from: html, pattern: murlPattern)
            let turls = extractMatches(from: html, pattern: turlPattern)

            for i in 0..<min(murls.count, Self.pageSize) {
                let thumb = i < turls.count ? turls[i] : murls[i]
                results.append(CoverSearchResult(
                    thumbnailURL: thumb,
                    fullURL: murls[i]
                ))
            }

            imageResults = results
        } catch {
            AppLogger.warning("Bing error: \(error)", category: "CoverSearch")
        }
    }

    private func searchBaidu(encoded: String, offset: Int) async {
        // acjson JSON 端点：pn = 偏移量，rn = 每页数量。比 HTML 页更适合翻页
        guard let url = URL(string: "https://image.baidu.com/search/acjson?tn=resultjson_com&word=\(encoded)&pn=\(offset)&rn=\(Self.pageSize)") else { return }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("https://image.baidu.com/", forHTTPHeaderField: "Referer")
            request.timeoutInterval = 15

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = String(data: data, encoding: .utf8) else { return }

            var results: [CoverSearchResult] = []

            // acjson 返回的 JSON 常含非法控制字符，用正则按字段抽取更稳
            // 原图用 middleURL（objURL 是加密串，反正入库会压成缩略图，中图足够）
            let thumbURLs = extractMatches(from: json, pattern: #""thumbURL":"(https?:\\?/\\?/[^"]+?)""#)
            let middleURLs = extractMatches(from: json, pattern: #""middleURL":"(https?:\\?/\\?/[^"]+?)""#)

            for i in 0..<min(thumbURLs.count, Self.pageSize) {
                let thumb = unescapeJSONURL(thumbURLs[i])
                let full = i < middleURLs.count ? unescapeJSONURL(middleURLs[i]) : thumb
                results.append(CoverSearchResult(thumbnailURL: thumb, fullURL: full))
            }

            imageResults = results
        } catch {
            AppLogger.warning("Baidu error: \(error)", category: "CoverSearch")
        }
    }

    /// 还原 JSON 里被转义的斜杠（\/  →  /）
    private func unescapeJSONURL(_ s: String) -> String {
        s.replacingOccurrences(of: "\\/", with: "/")
    }

    private func extractMatches(from text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    /// 搜索结果原图最大允许 10MB（图床域名不可控，防超大图 OOM）
    private static let maxImageSize = 10 * 1024 * 1024

    private func selectImage(_ result: CoverSearchResult) async {
        // 图床域名不可控，无法套豆瓣白名单，但仍要求 https，防明文/SSRF
        guard let url = URL(string: result.fullURL), url.scheme == "https" else { return }
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            // 防超大响应耗尽内存
            guard data.count > 500, data.count <= Self.maxImageSize else { return }
            // 入口处统一压成缩略图（§4.1），避免未压缩大图驻留 State / 入库
            onSelect(CoverImageProcessor.thumbnailData(from: data))
            dismiss()
        } catch {
            AppLogger.warning("Download failed: \(error)", category: "CoverSearch")
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Book.self, Bookshelf.self, Tag.self, configurations: config)
    let book = Book(title: "测试书籍", author: "测试作者")
    container.mainContext.insert(book)
    return EditBookView(book: book)
        .modelContainer(container)
}
