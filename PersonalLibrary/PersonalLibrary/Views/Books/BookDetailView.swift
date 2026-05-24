import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Bindable var book: Book
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddRecord = false
    @State private var showingEditBook = false
    @State private var showArchiveAlert = false
    @State private var coverImage: UIImage?

    private var bookTypeIcon: String {
        switch book.bookType {
        case .paper: return "book.closed"
        case .ebook: return "ipad"
        case .audiobook: return "headphones"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 书籍基本信息
                bookInfoSection

                // 书籍简介
                if let desc = book.bookDescription, !desc.isEmpty {
                    descriptionSection(title: "书籍简介", text: desc)
                }

                // 作者简介
                if let desc = book.authorDescription, !desc.isEmpty {
                    descriptionSection(title: "作者简介", text: desc)
                }

                // 备注
                notesSection

                // 阅读记录
                readingRecordsSection
            }
            .padding()
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingEditBook = true
                    } label: {
                        Image(systemName: "pencil")
                    }

                    Menu {
                        // 阅读状态
                        ForEach(ReadingStatus.allCases, id: \.self) { status in
                            Button {
                                book.status = status
                                book.statusChangedDate = Date()
                                if status == .finished {
                                    book.finishedDate = Date()
                                }
                            } label: {
                                if book.status == status {
                                    Label(status.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(status.rawValue)
                                }
                            }
                        }

                        Divider()

                        // 评分
                        Menu("评分") {
                            ForEach(1...5, id: \.self) { stars in
                                Button {
                                    book.rating = stars
                                } label: {
                                    if book.rating == stars {
                                        Label(String(repeating: "★", count: stars), systemImage: "checkmark")
                                    } else {
                                        Text(String(repeating: "★", count: stars))
                                    }
                                }
                            }
                            Button("清除评分") {
                                book.rating = nil
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            showArchiveAlert = true
                        } label: {
                            Label("取消收藏", systemImage: "heart.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditBook) {
            EditBookView(book: book)
        }
        .onChange(of: showingEditBook) { _, isShowing in
            // 编辑页关闭后，封面可能被更新，刷新 @State
            if !isShowing, let data = book.coverImageData, let img = UIImage(data: data) {
                coverImage = img
            }
        }
        .sheet(isPresented: $showingAddRecord) {
            AddReadingRecordView(book: book)
        }
        .alert("取消收藏", isPresented: $showArchiveAlert) {
            Button("取消收藏", role: .destructive) {
                book.isArchived = true
                try? modelContext.save()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("取消收藏后，此书将不再显示在藏书列表中。\n你可以通过高级搜索找回并恢复收藏。")
        }
        .task {
            await loadCover()
            await fetchWeReadInfoIfNeeded()
        }
    }

    private var bookInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 封面 + 标题区
            HStack(alignment: .top, spacing: 16) {
                // 封面：由 @State coverImage 驱动，避免 externalStorage 观察问题
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(radius: 2)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(book.author)
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    if let publisher = book.publisher {
                        Label(publisher, systemImage: "building.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        if book.totalPages > 0 {
                            Label("\(book.totalPages) 页", systemImage: "doc")
                                .font(.caption)
                        }
                        if let price = book.price {
                            Label(price, systemImage: "yensign.circle")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        StatusBadge(status: book.status)
                        Label(book.bookType.rawValue, systemImage: bookTypeIcon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // 评分
                    if let rating = book.rating {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.caption)
                                    .foregroundStyle(star <= rating ? .yellow : .gray.opacity(0.3))
                            }
                        }
                    }
                }
            }

            // 书架
            if let shelf = book.bookshelf {
                Label(shelf.name, systemImage: shelf.icon)
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }

            // 标签
            if let tags = book.tags, !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags) { tag in
                        Text(tag.name)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func descriptionSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 备注

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注")
                .font(.headline)

            TextEditor(text: Binding(
                get: { book.notes ?? "" },
                set: { newValue in
                    let trimmed = String(newValue.prefix(5000))
                    book.notes = trimmed.isEmpty ? nil : trimmed
                    try? modelContext.save()
                }
            ))
            .frame(minHeight: 80, maxHeight: 200)
            .padding(8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Text("\(book.notes?.count ?? 0)/5000")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }

            if book.notes == nil || book.notes!.isEmpty {
                Text("点击上方输入备注...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var readingRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("阅读记录")
                    .font(.headline)
                Spacer()
                Button("记录阅读") {
                    showingAddRecord = true
                }
                .font(.subheadline)
            }

            if (book.readingRecords ?? []).isEmpty {
                Text("还没有阅读记录，开始读书吧！")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach((book.readingRecords ?? []).sorted(by: { $0.date > $1.date })) { record in
                    ReadingRecordRow(record: record)
                }
            }
        }
    }

    // MARK: - 封面加载（@State 驱动，绕过 externalStorage 观察问题）

    private func loadCover() async {
        // 1. 本地 DB 有数据 → 直接解码到 @State + 写入内存缓存
        if let data = book.coverImageData, !data.isEmpty,
           let img = UIImage(data: data) {
            coverImage = img
            let cacheKey = "\(book.title)|\(book.author)"
            CoverImageCache.shared.set(img, for: cacheKey)
            return
        }

        // 2. 内存缓存（列表可能已经下载过）
        let cacheKey = "\(book.title)|\(book.author)"
        if let cached = CoverImageCache.shared.image(for: cacheKey) {
            coverImage = cached
            // 顺便持久化到 DB，后续不再需要网络
            if book.coverImageData == nil {
                book.coverImageData = cached.jpegData(compressionQuality: 0.85)
                try? modelContext.save()
            }
            return
        }

        // 3. 网络下载（完整 pipeline）
        let data = await CoverFetchService.shared.fetchCoverThrottled(
            coverImageURL: book.coverImageURL,
            isbn: book.isbn,
            doubanURL: book.doubanURL,
            title: book.title,
            author: book.author
        )

        guard let data, let img = UIImage(data: data) else { return }
        coverImage = img
        // 写入内存缓存，供编辑页读取（避免 externalStorage 延迟问题）
        CoverImageCache.shared.set(img, for: cacheKey)
        // 持久化
        if book.coverImageData == nil {
            book.coverImageData = data
            try? modelContext.save()
        }
    }

    // MARK: - WeRead 详情按需补全

    private func fetchWeReadInfoIfNeeded() async {
        // 只对微信读书导入、缺出版社的书触发
        guard let bookId = book.wereadBookId,
              (book.publisher == nil || book.publisher?.isEmpty == true) else {
            return
        }

        let service = WeReadService()
        guard await service.isLoggedIn() else { return }

        do {
            let info = try await service.fetchBookInfo(bookId: bookId)
            if let publisher = info.publisher, !publisher.isEmpty {
                book.publisher = publisher
            }
            if let isbn = info.isbn, !isbn.isEmpty, book.isbn == nil {
                book.isbn = isbn
            }
            if let intro = info.intro, !intro.isEmpty, book.bookDescription == nil {
                book.bookDescription = intro
            }
            if let price = info.price, price > 0, book.price == nil {
                book.price = "¥\(String(format: "%.2f", price))"
            }
            if let publishTime = info.publishTime, !publishTime.isEmpty, book.publishDate == nil {
                let formatter = DateFormatter()
                for format in ["yyyy-MM-dd", "yyyy-MM", "yyyy"] {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: publishTime) {
                        book.publishDate = date
                        break
                    }
                }
            }
            if let type = info.type, (type == 2 || type == 3), book.bookType != .audiobook {
                book.bookType = .audiobook
            }
            try? modelContext.save()
        } catch {
            print("[BookDetail] WeRead info fetch failed: \(error)")
        }
    }
}

struct ReadingRecordRow: View {
    let record: ReadingRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.date, style: .date)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("第 \(record.startPage) - \(record.endPage) 页（\(record.pagesRead) 页）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if record.durationMinutes > 0 {
                Text("\(record.durationMinutes) 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
