import SwiftUI
import SwiftData
import PhotosUI
import WebKit

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
    /// 选定/搜到的原图，进裁剪编辑器；裁剪确定后才落地为封面
    @State private var cropTarget: CropTarget?

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
                    coverData = imageData  // 已在搜索页内部裁剪+压缩（§4.1）
                }
            }
            .fullScreenCover(item: $cropTarget) { target in
                CoverCropView(image: target.image) { cropped in
                    applyCroppedCover(cropped)
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
                                    presentCrop(data)
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
                    presentCrop(imageData)
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

    // MARK: - 封面裁剪

    /// 任意来源拿到原图字节后，先进裁剪编辑器。
    /// 用限尺寸解码（≤maxCropPixel）防 pixel-bomb OOM；解码失败则直接压缩原图兜底（不丢数据）。
    private func presentCrop(_ data: Data?) {
        guard let data, let image = CoverCropGeometry.decodeForCropping(data) else {
            if let data { coverData = CoverImageProcessor.thumbnailData(from: data) }
            return
        }
        cropTarget = CropTarget(image: image)
    }

    /// 裁剪确定后，统一压成缩略图（§4.1）再落地为封面
    private func applyCroppedCover(_ image: UIImage) {
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
        coverData = CoverImageProcessor.thumbnailData(from: jpeg)
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

// MARK: - 封面网络搜索（内置浏览器 + 长按取图）

/// 封面网络搜索：内置浏览器加载 Google/百度/Bing 图片搜索真实网页，
/// 用户长按图片选"选做封面"。相比自己抓 URL，排序由搜索引擎负责、缩略图在真实会话内渲染，
/// 相关性与防盗链问题都不复存在。
struct CoverWebSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let bookTitle: String
    let bookAuthor: String
    let onSelect: (Data) -> Void

    enum SearchEngine: String, CaseIterable, Identifiable {
        case google = "Google"
        case baidu = "百度"
        case bing = "Bing"
        var id: String { rawValue }
    }

    @State private var engine: SearchEngine?
    /// 长按选中、下载好的原图，进裁剪窗；取消则回到搜索结果（不关搜索页）
    @State private var cropTarget: CropTarget?

    /// 搜索关键词（书名 + 作者，避免泛词稀释相关性）
    private var query: String {
        "\(bookTitle) \(bookAuthor)".trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let engine {
                    CoverBrowser(url: CoverSearchURL.make(engine: engine, query: query)) { data in
                        // 下载到原图，限尺寸解码后进裁剪窗（不在此压缩，保留分辨率给裁剪）
                        if let image = CoverCropGeometry.decodeForCropping(data) {
                            cropTarget = CropTarget(image: image)
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(bookTitle.isEmpty ? "搜索封面" : bookTitle)
                    .navigationBarTitleDisplayMode(.inline)
                } else {
                    enginePicker
                        .navigationTitle("搜索封面")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if engine != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("换引擎") { engine = nil }
                    }
                }
            }
            // 裁剪窗在搜索页内部弹出：取消 → 回搜索结果；确定 → 压缩回传并关闭搜索页
            .fullScreenCover(item: $cropTarget) { target in
                CoverCropView(image: target.image) { cropped in
                    if let jpeg = cropped.jpegData(compressionQuality: 0.9) {
                        onSelect(CoverImageProcessor.thumbnailData(from: jpeg))
                        dismiss()
                    }
                }
            }
        }
    }

    // 引擎选择页
    private var enginePicker: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("选择搜索来源")
                .font(.headline)
            Text("打开网页后，长按目标封面图片，选「选做封面」")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            ForEach(SearchEngine.allCases) { e in
                Button {
                    engine = e
                } label: {
                    Text(e.rawValue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 40)
            }
        }
        .padding(.top, 40)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - 封面搜索 URL 构造（独立出来便于单测）

enum CoverSearchURL {
    /// RFC3986 unreserved 字符集；其余（含 & ? # = 等保留字）全部编码，避免关键词被 URL 解析截断
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func make(engine: CoverWebSearchView.SearchEngine, query: String) -> URL {
        let q = query.addingPercentEncoding(withAllowedCharacters: unreserved) ?? query
        let s: String
        switch engine {
        case .google:
            s = "https://www.google.com/search?q=\(q)&tbm=isch"
        case .baidu:
            // 移动端图片搜索入口：版式响应式、对非标准 UA 的风控比 PC 站宽松。
            // tn=vsearch&atn=page 必带，否则 m.baidu.com 会把请求重定向回首页、不执行搜索。
            s = "https://m.baidu.com/sf/vsearch?pd=image_content&tn=vsearch&atn=page&word=\(q)"
        case .bing:
            s = "https://www.bing.com/images/search?q=\(q)"
        }
        return URL(string: s) ?? URL(string: "https://www.bing.com")!
    }
}

// MARK: - 封面字节解析（独立出来便于单测，不依赖网络/WebView）

enum CoverImageBytes {
    /// 原图最大 10MB，防超大图 OOM
    static let maxBytes = 10 * 1024 * 1024

    /// data:image/...;base64,xxxx → 解码后的二进制；非 data-uri 或解码失败返回 nil
    static func decodeDataURI(_ src: String) -> Data? {
        guard src.hasPrefix("data:"),
              let comma = src.range(of: "base64,") else { return nil }
        let encoded = src[comma.upperBound...]
        // 解码前先卡 base64 串长度，防超大 payload 在解码时撑爆内存。
        // base64 长度 = 4*ceil(n/3)，对 n=maxBytes 取上界并留余量（padding/换行），
        // 避免把恰好 maxBytes 的合法数据误判为超限。
        guard encoded.count <= (maxBytes + 2) / 3 * 4 + 16 else { return nil }
        guard let data = Data(base64Encoded: String(encoded),
                              options: .ignoreUnknownCharacters),
              data.count > 100, data.count <= maxBytes else { return nil }
        return data
    }

    /// 校验通过网络下载的数据是否可用作封面（大小区间）
    static func isAcceptable(_ data: Data) -> Bool {
        data.count > 100 && data.count <= maxBytes
    }

    /// 从页面 URL 推导下载时该带的 Referer（防盗链）
    static func referer(for pageURL: URL?) -> String {
        guard let pageURL, let host = pageURL.host else { return "" }
        return "\(pageURL.scheme ?? "https")://\(host)/"
    }

    /// 校验图片 src 是否可安全下载：仅 https + 阻断内网/本地/特殊主机（SSRF 防护）。
    /// 不做域名白名单——搜索引擎图床域名无法穷举，白名单会误杀真实封面；
    /// 改为阻断内网目标，兼顾安全与可用。
    static func isDownloadable(_ src: String) -> Bool {
        guard let url = URL(string: src), url.scheme == "https",
              let rawHost = url.host?.lowercased(), !rawHost.isEmpty,
              // host 不能只由点组成（"." / ".jpg" 等畸形 host）
              !rawHost.allSatisfy({ $0 == "." }), rawHost.first != "." else { return false }
        // 先把十进制/八进制/十六进制等非点分 IPv4 编码规范化成点分十进制，
        // 否则 "2130706433"/"0x7f.0.0.1" 这类会绕过下面的 hasPrefix 网段检查（SSRF）。
        let host = canonicalizedIPv4(rawHost) ?? rawHost
        // localhost / .local
        if host == "localhost" || host.hasSuffix(".local") { return false }
        // IPv4 回环 / 任意地址 / 内网网段 / link-local
        if host == "127.0.0.1" || host == "0.0.0.0" { return false }
        if host.hasPrefix("127.") { return false }   // 整个 127/8 回环段
        if host.hasPrefix("10.") || host.hasPrefix("192.168.")
            || host.hasPrefix("169.254.") { return false }
        // 172.16.0.0–172.31.255.255
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) { return false }
        }
        // IPv6（URL.host 已去掉方括号）：回环 ::1、link-local fe80::/10、ULA fc00::/7、IPv4 映射
        if host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") { return false }
        if host.hasPrefix("::ffff:") { return false }   // IPv4-mapped IPv6，避免映射内网地址绕过
        return true
    }

    /// 把任意合法 IPv4 表示（十进制 2130706433 / 十六进制 0xc0a80101 / 八进制 / 点分混合）
    /// 规范化成点分十进制 "a.b.c.d"；非 IPv4 主机（域名/IPv6）返回 nil。
    /// 用 inet_aton（支持所有历史 IPv4 写法），再用 inet_ntop 转回标准点分。
    static func canonicalizedIPv4(_ host: String) -> String? {
        // 必须全部由 IPv4 允许的字符组成，排除域名（含字母 g-z、连字符等）
        guard !host.isEmpty,
              host.allSatisfy({ $0.isHexDigit || $0 == "." || $0 == "x" || $0 == "X" }) else { return nil }
        var addr = in_addr()
        guard inet_aton(host, &addr) == 1 else { return nil }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buf)
    }

    /// 剥离 HTTP 头值里的 CR/LF 与控制字符，防止页面可控的 navigator.userAgent
    /// 注入额外请求头（CRLF injection）。
    static func sanitizeHeaderValue(_ value: String) -> String {
        value.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }
}

// MARK: - WKWebView 封装（长按图片 → 选做封面）

private struct CoverBrowser: UIViewRepresentable {
    let url: URL
    let onPick: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()  // 隔离会话，不持久化第三方 cookie（与 WeReadLoginView 一致）
        // 抑制 img 长按的系统存图菜单，让我们的长按手势接管
        cfg.userContentController.addUserScript(WKUserScript(
            source: Self.calloutSuppressionJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false))

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.allowsBackForwardNavigationGestures = true
        // 不设 customUserAgent：用系统默认 Safari UA，更像真实浏览器，降低被风控/弹验证码概率
        web.load(URLRequest(url: url))

        // iOS WKWebView 不触发 JS contextmenu，改用原生长按手势 + elementFromPoint 取 img src
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:)))
        longPress.delegate = context.coordinator
        web.addGestureRecognizer(longPress)

        context.coordinator.webView = web
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    /// 注入 CSS 抑制 img 的系统长按菜单（存储图片等）
    static let calloutSuppressionJS = """
    (function() {
      var s = document.createElement('style');
      s.textContent = 'img { -webkit-touch-callout: none !important; }';
      (document.head || document.documentElement).appendChild(s);
    })();
    """

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onPick: (Data) -> Void
        weak var webView: WKWebView?

        init(onPick: @escaping (Data) -> Void) { self.onPick = onPick }

        // 与 WebView 内部手势共存
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let webView else { return }
            // 布局未完成时 bounds 为 0，避免除零（→ JS Infinity → elementFromPoint 失效）
            guard webView.bounds.width > 0, webView.bounds.height > 0 else { return }
            let pt = gesture.location(in: webView)
            // 屏幕坐标 → 视口坐标（考虑缩放与滚动），再用 elementFromPoint 取 img src
            let js = """
            (function() {
              var sx = window.innerWidth / \(Int(webView.bounds.width));
              var sy = window.innerHeight / \(Int(webView.bounds.height));
              var x = \(Int(pt.x)) * sx, y = \(Int(pt.y)) * sy;
              var el = document.elementFromPoint(x, y);
              if (!el) return '';
              if (el.tagName === 'IMG') return el.currentSrc || el.src || '';
              // 命中祖先 img（图片被包在链接里时）
              var img = el.closest && el.closest('img');
              // 命中容器内的子 img（点到链接的 padding 区域时）
              if (!img && el.querySelector) img = el.querySelector('img');
              if (img) return img.currentSrc || img.src || '';
              if (el.dataset && el.dataset.src) return el.dataset.src;
              return '';
            })();
            """
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, let src = result as? String, !src.isEmpty else { return }
                // evaluateJavaScript 回调线程不保证主线程，present UIAlertController 必须切主线程
                DispatchQueue.main.async { self.confirmSelection(src: src, at: pt) }
            }
        }

        /// 长按命中图片后，弹「选做封面 / 取消」确认菜单，确认才下载
        private func confirmSelection(src: String, at point: CGPoint) {
            guard let webView, let presenter = webView.findViewController(),
                  presenter.presentedViewController == nil else { return }  // 防连续长按重复弹出
            let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "选做封面", style: .default) { [weak self] _ in
                self?.handle(src: src)
            })
            sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
            // iPad：actionSheet 需锚点，锚到长按位置避免崩溃
            if let pop = sheet.popoverPresentationController {
                pop.sourceView = webView
                pop.sourceRect = CGRect(origin: point, size: .zero)
            }
            presenter.present(sheet, animated: true)
        }

        // 三层取字节：data-uri 直接解码 / 否则带 Referer 下载
        private func handle(src: String) {
            if src.hasPrefix("data:") {
                if let data = CoverImageBytes.decodeDataURI(src) { deliver(data) }
                return
            }
            guard CoverImageBytes.isDownloadable(src), let url = URL(string: src) else { return }
            let referer = CoverImageBytes.referer(for: webView?.url)
            // 取浏览器真实 UA，保持下载与浏览一致（防盗链/风控对 UA 不一致敏感）
            webView?.evaluateJavaScript("navigator.userAgent") { [weak self] ua, _ in
                self?.download(url: url, referer: referer, userAgent: ua as? String)
            }
        }

        private func download(url: URL, referer: String, userAgent: String?) {
            var req = URLRequest(url: url)
            req.setValue(CoverImageBytes.sanitizeHeaderValue(referer), forHTTPHeaderField: "Referer")
            // userAgent 取自页面可控的 navigator.userAgent，剥离 CRLF 防头注入
            if let userAgent {
                req.setValue(CoverImageBytes.sanitizeHeaderValue(userAgent), forHTTPHeaderField: "User-Agent")
            }
            req.timeoutInterval = 15
            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                guard let self, let data, CoverImageBytes.isAcceptable(data) else { return }
                self.deliver(data)
            }.resume()
        }

        private func deliver(_ data: Data) {
            DispatchQueue.main.async { self.onPick(data) }
        }
    }
}

private extension UIView {
    /// 沿响应链找到承载本视图的 UIViewController，用于 present 确认菜单
    func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
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
