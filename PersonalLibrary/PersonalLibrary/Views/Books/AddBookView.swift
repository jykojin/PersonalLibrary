import SwiftUI
import SwiftData

struct AddBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Bookshelf.sortOrder) private var bookshelves: [Bookshelf]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    // ISBN 扫描
    @State private var isbn = ""
    @State private var scannedISBN: String?
    @State private var showingScanner = false
    @State private var isLookingUp = false
    @State private var lookupError: String?

    // 书籍信息
    @State private var title = ""
    @State private var author = ""
    @State private var publisher = ""
    @State private var totalPages = ""
    @State private var price = ""
    @State private var bookDescription = ""
    @State private var authorDescription = ""

    // 封面
    @State private var coverImageData: Data?
    @State private var coverImageURL: String?
    @State private var doubanURL: String?

    // 类型 & 状态 & 评分
    @State private var bookType: BookType = .paper
    @State private var readingStatus: ReadingStatus = .idle
    @State private var rating: Int?

    // 书架 & 标签
    @State private var selectedBookshelf: Bookshelf?
    @State private var selectedTags: Set<Tag> = []
    @State private var showingNewTag = false
    @State private var newTagName = ""

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
                }

                // MARK: - 封面预览
                if let imageData = coverImageData,
                   let uiImage = UIImage(data: imageData) {
                    Section("封面") {
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
                }

                // MARK: - 基本信息
                Section("基本信息") {
                    TextField("书名", text: $title)
                    TextField("作者", text: $author)
                    TextField("出版社", text: $publisher)
                    TextField("总页数", text: $totalPages)
                        .keyboardType(.numberPad)
                    TextField("价格（如 ¥59.00）", text: $price)
                }

                // MARK: - 类型 & 状态
                Section("类型与状态") {
                    Picker("书籍类型", selection: $bookType) {
                        ForEach(BookType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

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
                    if !allTags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(allTags) { tag in
                                TagChip(
                                    tag: tag,
                                    isSelected: selectedTags.contains(tag)
                                ) {
                                    if selectedTags.contains(tag) {
                                        selectedTags.remove(tag)
                                    } else {
                                        selectedTags.insert(tag)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        showingNewTag = true
                    } label: {
                        Label("添加新标签", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("添加新书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveBook() }
                        .disabled(title.isEmpty || author.isEmpty)
                }
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView(scannedISBN: $scannedISBN, isPresented: $showingScanner)
            }
            .onChange(of: scannedISBN) { _, newValue in
                if let newValue, !newValue.isEmpty {
                    isbn = newValue
                    Task { await performLookup(isbn: newValue) }
                }
            }
            .alert("新标签", isPresented: $showingNewTag) {
                TextField("标签名称", text: $newTagName)
                Button("取消", role: .cancel) { newTagName = "" }
                Button("添加") { createNewTag() }
            }
        }
    }

    // MARK: - ISBN Lookup

    private func performLookup(isbn: String) async {
        guard !isbn.isEmpty else { return }
        isLookingUp = true
        lookupError = nil

        do {
            if let result = try await lookupService.lookup(isbn: isbn) {
                title = result.title
                author = result.author
                publisher = result.publisher ?? ""
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
            } else {
                lookupError = "未找到该 ISBN 对应的书籍信息"
            }
        } catch {
            lookupError = "查询失败：\(error.localizedDescription)"
        }

        isLookingUp = false
    }

    // MARK: - Save

    private func saveBook() {
        let book = Book(
            title: title.trimmingCharacters(in: .whitespaces),
            author: author.trimmingCharacters(in: .whitespaces),
            isbn: isbn.isEmpty ? nil : isbn,
            publisher: publisher.isEmpty ? nil : publisher,
            totalPages: Int(totalPages) ?? 0,
            price: price.isEmpty ? nil : price,
            doubanURL: doubanURL,
            bookType: bookType,
            bookDescription: bookDescription.isEmpty ? nil : bookDescription,
            authorDescription: authorDescription.isEmpty ? nil : authorDescription,
            coverImageURL: coverImageURL
        )
        book.coverImageData = coverImageData
        book.status = readingStatus
        book.statusChangedDate = Date()
        book.rating = rating
        book.bookshelf = selectedBookshelf
        book.tags = Array(selectedTags)
        book.addSource = scannedISBN != nil ? .scanned : .manual

        modelContext.insert(book)
        dismiss()
    }

    // MARK: - Tag Creation

    private func createNewTag() {
        guard !newTagName.isEmpty else { return }
        let tag = Tag(name: newTagName.trimmingCharacters(in: .whitespaces))
        modelContext.insert(tag)
        selectedTags.insert(tag)
        newTagName = ""
    }
}

// MARK: - Tag Chip View

struct TagChip: View {
    let tag: Tag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tag.name)
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
