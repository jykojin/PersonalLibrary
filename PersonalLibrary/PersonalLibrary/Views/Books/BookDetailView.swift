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
    @State private var notesText: String = ""
    @State private var notesInitialized = false
    @State private var saveTask: Task<Void, Never>?

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

                // 加入日期
                Text("加入：\(book.addedDate, format: .dateTime.year().month().day())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                        if let date = book.publishDate {
                            Label(Self.publishDateFormatter.string(from: date), systemImage: "calendar")
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

            TextEditor(text: $notesText)
                .frame(minHeight: 80, maxHeight: 200)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    Text("\(notesText.count)/5000")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .onAppear {
                    if !notesInitialized {
                        notesText = book.notes ?? ""
                        notesInitialized = true
                    }
                }
                .onChange(of: notesText) { _, newValue in
                    saveTask?.cancel()
                    saveTask = Task {
                        try? await Task.sleep(for: .milliseconds(800))
                        if Task.isCancelled { return }
                        await MainActor.run {
                            performNotesSave(newValue)
                        }
                    }
                }
                .onDisappear {
                    saveTask?.cancel()
                    performNotesSave(notesText)
                }

            if notesText.isEmpty {
                Text("点击上方输入备注...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func performNotesSave(_ value: String) {
        let trimmed = String(value.prefix(5000))
        book.notes = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
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

            // 阅读时间线：开始阅读 → 累计时长 → 读完
            if book.startedReadingDate != nil || book.wereadReadingHours > 0 || (book.status == .finished && book.finishedDate != nil) {
                VStack(alignment: .leading, spacing: 4) {
                    if let startDate = book.startedReadingDate {
                        Label("开始阅读于 \(startDate, style: .date)", systemImage: "play.circle")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                    if let summary = book.readingSummaryText {
                        Label(summary, systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                    if book.status == .finished, let date = book.finishedDate {
                        Label("读完于 \(date, style: .date)", systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)
            }

            if (book.readingRecords ?? []).isEmpty {
                if book.wereadReadingHours == 0 {
                    Text("还没有阅读记录，开始读书吧！")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            } else {
                ForEach((book.readingRecords ?? []).sorted(by: { $0.date > $1.date })) { record in
                    ReadingRecordRow(record: record)
                }
            }
        }
    }

    // MARK: - Formatters

    private static let publishDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    // MARK: - 封面加载（@State 驱动，绕过 externalStorage 观察问题）

    private func loadCover() async {
        let cacheKey = "\(book.title)|\(book.author)"

        // 1. 本地 DB 有数据 → 直接解码到 @State
        if book.hasCoverData, let data = book.coverImageData,
           let img = UIImage(data: data) {
            coverImage = img
            return
        }

        // 2. 内存缓存（列表可能已经下载过）
        if let cached = CoverImageCache.shared.image(for: cacheKey) {
            coverImage = cached
            // 顺便持久化到 DB，后续不再需要网络
            if !book.hasCoverData {
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
        // 持久化
        if !book.hasCoverData {
            book.coverImageData = data
            try? modelContext.save()
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
