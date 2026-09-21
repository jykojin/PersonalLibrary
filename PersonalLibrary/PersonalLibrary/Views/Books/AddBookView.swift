import SwiftUI
import SwiftData

struct AddBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Bookshelf.sortOrder) private var bookshelves: [Bookshelf]

    // ISBN 扫描
    @State private var isbn = ""
    @State private var scannedISBN: String?
    @State private var showingScanner = false
    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var duplicateBook: Book?
    @State private var showDuplicateAlert = false
    /// 同 ISBN 已有其它载体版本时的温和提示（不拦截添加）
    @State private var otherEditionHint: String?

    // 智能补全
    @State private var isSmartFilling = false
    @State private var smartFillMessage: String?
    @State private var smartFillTask: Task<Void, Never>?
    @State private var aiAvailability = AIConfigAvailability.shared
    @State private var enrichmentCommitMarkers = EnrichmentManualCommitMarkers()

    // 书籍信息
    @State private var title = ""
    @State private var author = ""
    @State private var translator = ""
    @State private var publisher = ""
    @State private var publishDateText = ""
    @State private var totalPages = ""
    @State private var price = ""
    @State private var bookDescription = ""
    @State private var authorDescription = ""
    @State private var bookIntroduction = ""

    // 封面
    @State private var coverImageData: Data?
    @State private var coverImageURL: String?
    @State private var doubanURL: String?
    @State private var showWebSearch = false

    // 类型 & 状态 & 评分
    @State private var bookType: BookType = .paper
    @State private var readingStatus: ReadingStatus = .idle
    @State private var rating: Int?

    // 书架 & 标签
    @State private var selectedBookshelf: Bookshelf?
    @State private var selectedTags: Set<String> = []  // 存标签名（与 EditBookView 一致），落库时按名查找或创建

    private let lookupService = ISBNLookupService()

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - ISBN 扫描区域
                Section("扫描 / 输入 ISBN") {
                    HStack {
                        TextField("ISBN", text: $isbn)
                            .keyboardType(.numberPad)

                        Button {
                            showingScanner = true
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                                .font(.title2)
                        }
                    }

                    Button {
                        Task { await performLookup(isbn: isbn) }
                    } label: {
                        HStack {
                            if isLookingUp {
                                ProgressView()
                                    .controlSize(.small)
                                Text("查询中...")
                            } else {
                                Image(systemName: "magnifyingglass")
                                Text("查询书籍信息")
                            }
                        }
                    }
                    .disabled(isbn.isEmpty || isLookingUp)

                    if let error = lookupError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // 同 ISBN 已有其它载体版本：只提示，不拦截
                    if let hint = otherEditionHint {
                        Label(hint, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                // MARK: - 封面
                Section("封面") {
                    VStack(spacing: 12) {
                        if let imageData = coverImageData,
                           let uiImage = UIImage(data: imageData) {
                            HStack {
                                Spacer()
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(radius: 2)
                                Spacer()
                            }
                        }

                        // 始终提供手动搜索封面入口（ISBN 没匹配到封面时也能补）
                        Button {
                            showWebSearch = true
                        } label: {
                            Label(coverImageData == nil ? "搜索封面" : "重新搜索封面",
                                  systemImage: "magnifyingglass")
                        }
                    }
                }

                // MARK: - 基本信息
                Section("基本信息") {
                    TextField("书名", text: $title)
                    TextField("作者", text: $author)
                    TextField("译者", text: $translator)
                    TextField("出版社", text: $publisher)
                    TextField("出版日期（YYYY-MM-DD）", text: $publishDateText)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("总页数", text: $totalPages)
                        .keyboardType(.numberPad)
                    TextField("价格（如 ¥59.00）", text: $price)
                }

                // MARK: - 智能补全
                Section {
                    if isSmartFilling {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("补全中...")
                            Spacer()
                            Button("停止补全", role: .cancel) {
                                smartFillTask?.cancel()
                            }
                        }
                    } else {
                        Button {
                            startSmartFill(mode: .full)
                        } label: {
                            Label("智能补全书籍信息", systemImage: "wand.and.stars")
                        }
                        .disabled(!EnrichmentEntryPolicy.canStart(title: title, isbn: isbn))

                        Button {
                            startSmartFill(mode: .aiOnly)
                        } label: {
                            Label("AI智能补全", systemImage: "sparkles")
                        }
                        .disabled(
                            !EnrichmentEntryPolicy.canStart(title: title, isbn: isbn)
                            || !aiAvailability.isAvailable
                        )

                        if !aiAvailability.isAvailable {
                            NavigationLink("配置 AI 智能补全") {
                                AISettingsView()
                            }
                            .font(.caption)
                        }
                    }

                    if let message = smartFillMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - 类型 & 状态
                Section("类型与状态") {
                    Picker("书籍类型", selection: $bookType) {
                        ForEach(BookType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    // 改类型后原提示可能已不适用（如从纸质书改成电子书），先清掉
                    .onChange(of: bookType) { _, _ in otherEditionHint = nil }

                    Picker("阅读状态", selection: $readingStatus) {
                        ForEach(ReadingStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }

                    // 评分
                    HStack {
                        Text("评分")
                        Spacer()
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                if rating == star {
                                    rating = nil  // 再次点击取消
                                } else {
                                    rating = star
                                }
                            } label: {
                                Image(systemName: (rating ?? 0) >= star ? "star.fill" : "star")
                                    .foregroundStyle((rating ?? 0) >= star ? .yellow : .gray.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // MARK: - 简介
                Section("简介") {
                    DisclosureGroup("书籍简介") {
                        TextEditor(text: $bookDescription)
                            .frame(minHeight: 80)
                    }
                    DisclosureGroup("作者简介") {
                        TextEditor(text: $authorDescription)
                            .frame(minHeight: 80)
                    }
                    DisclosureGroup("AI简介") {
                        TextEditor(text: $bookIntroduction)
                            .frame(minHeight: 120)
                    }
                }

                // MARK: - 书架
                Section("书架") {
                    Picker("选择书架", selection: $selectedBookshelf) {
                        Text("无").tag(nil as Bookshelf?)
                        ForEach(bookshelves) { shelf in
                            Label(shelf.name, systemImage: shelf.icon)
                                .tag(shelf as Bookshelf?)
                        }
                    }
                }

                // MARK: - 标签
                Section("标签") {
                    TagSelectionEditor(selectedTags: $selectedTags)
                }
            }
            .navigationTitle("添加新书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        smartFillTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveBook() }
                        .disabled(title.isEmpty || author.isEmpty || isSmartFilling)
                }
            }
            .interactiveDismissDisabled(isSmartFilling)
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView(scannedISBN: $scannedISBN, isPresented: $showingScanner)
            }
            .sheet(isPresented: $showWebSearch) {
                CoverWebSearchView(bookTitle: title, bookAuthor: author) { imageData in
                    coverImageData = imageData  // 已在搜索页内部裁剪+压缩（§4.1）
                }
            }
            .onChange(of: scannedISBN) { _, newValue in
                if let newValue, !newValue.isEmpty {
                    isbn = newValue
                    Task { await performLookup(isbn: newValue) }
                }
            }
            .onDisappear {
                if EnrichmentTaskLifecyclePolicy.shouldCancelOnDisappear(
                    isSceneActive: scenePhase == .active
                ) {
                    smartFillTask?.cancel()
                }
            }
            .onAppear {
                aiAvailability.refresh()
            }
            .alert("ISBN 重复", isPresented: $showDuplicateAlert) {
                Button("知道了", role: .cancel) {}
            } message: {
                if let book = duplicateBook {
                    Text("该 ISBN 对应的书籍「\(book.title)」已存在于您的藏书中。")
                }
            }
        }
    }

    // MARK: - ISBN Lookup

    private func performLookup(isbn: String) async {
        guard !isbn.isEmpty else { return }

        // ISBN 去重检查：只有"同 ISBN + 同载体"才算重复。
        // 同一本书的纸质版与电子版是两本书（常见于实体书 + 微信读书电子版都收），
        // 不能让已有的电子书拦住纸质书的添加。
        let existing = ISBNDuplicateChecker.findExisting(isbn: isbn, bookType: bookType, in: modelContext)
        if let existing {
            duplicateBook = existing
            showDuplicateAlert = true
            return
        }

        // 存在其它载体的版本 → 放行，但温和提示一下
        let otherEditions = ISBNDuplicateChecker.findOtherEditions(isbn: isbn, excluding: bookType, in: modelContext)
        if let other = otherEditions.first {
            otherEditionHint = "你已有这本书的\(other.bookType.rawValue)版「\(other.title)」，本次将新增\(bookType.rawValue)。"
        } else {
            otherEditionHint = nil
        }

        isLookingUp = true
        lookupError = nil

        do {
            if let result = try await lookupService.lookup(isbn: isbn) {
                title = result.title
                author = result.author
                publisher = result.publisher ?? ""
                translator = result.translator ?? ""
                publishDateText = result.publishDate ?? ""
                totalPages = result.totalPages.map { String($0) } ?? ""
                price = result.price ?? ""
                bookDescription = result.bookDescription ?? ""
                authorDescription = result.authorDescription ?? ""
                coverImageURL = result.coverImageURL
                doubanURL = result.doubanURL

                // 下载封面图片
                if let urlString = result.coverImageURL {
                    coverImageData = await CoverFetchService.shared.downloadWithReferer(urlStr: urlString)
                }

                // 作者简介如果网络没拿到，尝试本地 DB
                if authorDescription.isEmpty {
                    if let localDesc = findLocalAuthorDescription(for: result.author) {
                        authorDescription = localDesc
                    }
                }
            } else {
                lookupError = "未找到该 ISBN 对应的书籍信息"
            }
        } catch {
            lookupError = "查询失败：\(error.localizedDescription)"
        }

        isLookingUp = false
    }

    // MARK: - Smart Fill (手动触发，走书名搜索)

    private func startSmartFill(mode: EnrichmentMode) {
        smartFillTask = Task { await performSmartFill(mode: mode) }
    }

    private func performSmartFill(mode: EnrichmentMode = .full) async {
        guard EnrichmentEntryPolicy.canStart(title: title, isbn: isbn) else { return }
        isSmartFilling = true
        smartFillMessage = nil
        defer {
            isSmartFilling = false
            smartFillTask = nil
        }

        let draft = makeEnrichmentDraft()
        let outcome = await EnrichmentBackgroundExecution().run(
            named: mode == .aiOnly ? "AI智能补全" : "智能补全书籍信息"
        ) {
            await EnrichmentCoordinator.live().enrich(
                draft,
                mode: mode,
                localAuthorDescription: findLocalAuthorDescription(for: author)
            )
        }
        let appliedOutcome = outcome.rebased(on: makeEnrichmentDraft())
        applyEnrichedDraft(appliedOutcome.draft)
        enrichmentCommitMarkers.record(appliedOutcome, mode: mode)

        if appliedOutcome.termination == .cancelled || Task.isCancelled {
            smartFillMessage = "已停止补全"
            return
        }

        if appliedOutcome.changedFields.isEmpty {
            if appliedOutcome.aiStatus == .notAttempted && mode == .aiOnly {
                smartFillMessage = "请先在设置中完成支持联网检索的 AI 配置"
            } else if let issue = appliedOutcome.aiIssueDescription {
                smartFillMessage = "补全未完成：\(issue)"
            } else {
                smartFillMessage = "未找到可补全的信息"
            }
        } else {
            let tokenText = appliedOutcome.tokenUsage.total.map { "，Token：\($0)" } ?? ""
            let issueText = appliedOutcome.aiIssueDescription.map { "；AI \($0)" } ?? ""
            smartFillMessage = "已补全 \(appliedOutcome.changedFields.count) 个字段\(tokenText)\(issueText)"
        }
    }

    private func makeEnrichmentDraft() -> BookDraft {
        BookDraft(
            title: title,
            author: author,
            translator: translator,
            isbn: isbn,
            publisher: publisher,
            publishDate: PublicationDateParser.parse(publishDateText),
            totalPages: Int(totalPages) ?? 0,
            price: price,
            bookDescription: bookDescription,
            authorDescription: authorDescription,
            aiIntroduction: bookIntroduction,
            rating: rating
        )
    }

    private func applyEnrichedDraft(_ draft: BookDraft) {
        title = draft.title
        author = draft.author
        translator = draft.translator ?? ""
        publisher = draft.publisher ?? ""
        publishDateText = PublicationDateParser.format(draft.publishDate)
        totalPages = draft.totalPages > 0 ? String(draft.totalPages) : ""
        price = draft.price ?? ""
        bookDescription = draft.bookDescription ?? ""
        authorDescription = draft.authorDescription ?? ""
        bookIntroduction = draft.aiIntroduction ?? ""
    }

    // MARK: - Local Author Description

    private func findLocalAuthorDescription(for authorName: String) -> String? {
        guard !authorName.isEmpty else { return nil }
        let name = authorName
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.author == name && $0.authorDescription != nil }
        )
        guard let matches = try? modelContext.fetch(descriptor) else { return nil }
        return matches
            .compactMap { $0.authorDescription }
            .filter { !$0.isEmpty }
            .max(by: { $0.count < $1.count })
    }

    // MARK: - Save

    private func saveBook() {
        // 在主线程收集值类型字段 + 关系标识（关系对象属于主 context，不能跨 context 传递）。
        // 全部写入放后台 context：主 context 被列表 @Query 注册了全部书，直接在主 context
        // insert/save 会 bridge 所有已注册对象造成卡顿（§4.2）。
        let container = modelContext.container
        let titleVal = title.trimmingCharacters(in: .whitespaces)
        let authorVal = author.trimmingCharacters(in: .whitespaces)
        let translatorVal = translator.trimmingCharacters(in: .whitespacesAndNewlines)
        let isbnVal = isbn.isEmpty ? nil : isbn
        let publisherVal = publisher.isEmpty ? nil : publisher
        let publishDateVal = PublicationDateParser.parse(publishDateText)
        let totalPagesVal = Int(totalPages) ?? 0
        let priceVal = price.isEmpty ? nil : price
        let doubanURLVal = doubanURL
        let bookTypeVal = bookType
        let bookDescVal = bookDescription.isEmpty ? nil : bookDescription
        let authorDescVal = authorDescription.isEmpty ? nil : authorDescription
        let bookIntroductionVal = bookIntroduction.isEmpty ? nil : bookIntroduction
        let coverURLVal = coverImageURL
        let rawCover = coverImageData
        let statusVal = readingStatus
        let ratingVal = rating
        let shelfID = selectedBookshelf?.persistentModelID
        let tagNames = Array(selectedTags)
        let source: AddSource = scannedISBN != nil ? .scanned : .manual
        let completedAt = Date()
        let lastEnrichmentDateVal = enrichmentCommitMarkers.shouldRecordMetadataCompletion
            ? completedAt
            : nil
        let lastAIEnrichmentDateVal = enrichmentCommitMarkers.shouldRecordAICompletion
            ? completedAt
            : nil

        dismiss()

        Task.detached(priority: .userInitiated) {
            let bg = ModelContext(container)
            bg.autosaveEnabled = false

            let book = Book(
                title: titleVal,
                author: authorVal,
                translator: translatorVal.isEmpty ? nil : translatorVal,
                isbn: isbnVal,
                publisher: publisherVal,
                publishDate: publishDateVal,
                totalPages: totalPagesVal,
                price: priceVal,
                doubanURL: doubanURLVal,
                bookType: bookTypeVal,
                bookDescription: bookDescVal,
                authorDescription: authorDescVal,
                coverImageURL: coverURLVal
            )
            book.coverImageData = rawCover.map { CoverImageProcessor.thumbnailData(from: $0) }  // 大图先压缩略图（后台线程）
            book.status = statusVal
            book.statusChangedDate = Date()
            book.rating = ratingVal
            book.bookIntroduction = bookIntroductionVal
            book.addSource = source
            book.lastEnrichmentDate = lastEnrichmentDateVal
            book.lastAIEnrichmentDate = lastAIEnrichmentDateVal

            // 书架：来自主 context @Query，按 ID 在后台 context 重新取
            if let shelfID, let shelf = bg.model(for: shelfID) as? Bookshelf {
                book.bookshelf = shelf
            }
            // 标签：按名字在后台 context 查找或创建（与 BatchTagView.applyTags 一致）
            if !tagNames.isEmpty {
                let existing = (try? bg.fetch(FetchDescriptor<Tag>())) ?? []
                var tagMap = Dictionary(existing.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
                var bookTags: [Tag] = []
                for name in tagNames {
                    if let tag = tagMap[name] {
                        bookTags.append(tag)
                    } else {
                        let tag = Tag(name: name)
                        bg.insert(tag)
                        tagMap[name] = tag
                        bookTags.append(tag)
                    }
                }
                book.tags = bookTags
            }

            bg.insert(book)
            bg.insert(ImportRecord(source: source.rawValue, totalCount: 1, successCount: 1))
            try? bg.save()
        }
    }

}

// MARK: - Tag Chip View

struct TagChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + lineHeight
        return ArrangementResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions,
            sizes: sizes
        )
    }

    struct ArrangementResult {
        var size: CGSize
        var positions: [CGPoint]
        var sizes: [CGSize]
    }
}

#Preview {
    AddBookView()
        .modelContainer(for: [Book.self, Bookshelf.self, Tag.self, ReadingRecord.self], inMemory: true)
}
