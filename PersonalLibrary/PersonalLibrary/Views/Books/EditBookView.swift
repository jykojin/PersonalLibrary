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
    @State private var currentPage: String = ""

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

    var body: some View {
        NavigationStack {
            Form {
                coverSection
                basicInfoSection
                typeAndStatusSection
                descriptionSection
                shelfAndTagsSection
            }
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
            MultiValueField(label: "作者", text: $author)
            MultiValueField(label: "译者", text: $translator)
            MultiValueField(label: "出版社", text: $publisher)
            EditLabeledField(label: "ISBN", text: $isbn)
            EditLabeledField(label: "定价", text: $price)
            EditLabeledField(label: "总页数", text: $totalPages)
                .keyboardType(.numberPad)
            EditLabeledField(label: "当前页", text: $currentPage)
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

            EditLabeledField(label: "豆瓣链接", text: $doubanURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
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
        currentPage = book.currentPage > 0 ? String(book.currentPage) : ""
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
    }

    private func saveChanges() {
        book.title = title.trimmingCharacters(in: .whitespaces)
        book.author = author.trimmingCharacters(in: .whitespaces)
        book.translator = translator.isEmpty ? nil : translator
        book.publisher = publisher.isEmpty ? nil : publisher
        book.isbn = isbn.isEmpty ? nil : isbn
        book.price = price.isEmpty ? nil : price
        book.totalPages = Int(totalPages) ?? 0
        book.currentPage = Int(currentPage) ?? 0
        book.publishDate = publishDate
        book.doubanURL = doubanURL.isEmpty ? nil : doubanURL
        book.bookType = bookType
        book.status = status
        book.statusChangedDate = Date()
        book.rating = rating > 0 ? rating : nil
        book.bookDescription = bookDescription.isEmpty ? nil : bookDescription
        book.authorDescription = authorDescription.isEmpty ? nil : authorDescription
        book.notes = notes.isEmpty ? nil : notes
        book.bookshelf = selectedShelf
        book.coverImageData = coverData

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

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - 多值标签字段（作者/译者/出版社）

private struct MultiValueField: View {
    let label: String
    @Binding var text: String
    @State private var inputText = ""

    private var items: [String] {
        text.components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标签列表
            if !items.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 3) {
                            Text(item)
                                .font(.subheadline)
                            Button {
                                removeItem(item)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                }
            }

            // 输入行
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                TextField("添加\(label)", text: $inputText)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { addCurrentInput() }
                if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        addCurrentInput()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    private func addCurrentInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = items
        current.append(trimmed)
        text = current.joined(separator: ", ")
        inputText = ""
    }

    private func removeItem(_ item: String) {
        var current = items
        current.removeAll { $0 == item }
        text = current.joined(separator: ", ")
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
    @State private var selectedEngine: SearchEngine = .google

    enum SearchEngine: String, CaseIterable {
        case google = "Google"
        case baidu = "百度"
    }

    struct CoverSearchResult: Identifiable {
        let id = UUID()
        let url: String
        let thumbnailURL: String
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

                // 搜索栏
                HStack {
                    TextField("搜索图书封面", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
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

    private func performSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isSearching = true
        imageResults = []

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL: String

        switch selectedEngine {
        case .google:
            searchURL = "https://www.google.com/search?q=\(encoded)&tbm=isch"
        case .baidu:
            searchURL = "https://image.baidu.com/search/index?tn=baiduimage&word=\(encoded)"
        }

        do {
            guard let url = URL(string: searchURL) else {
                isSearching = false
                return
            }
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else {
                isSearching = false
                return
            }

            let urls = parseImageURLs(from: html, engine: selectedEngine)
            imageResults = urls.prefix(12).map { CoverSearchResult(url: $0, thumbnailURL: $0) }
        } catch {
            print("[CoverSearch] Error: \(error)")
        }

        isSearching = false
    }

    private func parseImageURLs(from html: String, engine: SearchEngine) -> [String] {
        var urls: [String] = []

        switch engine {
        case .google:
            // Google 图片搜索结果中提取
            let pattern = #"https?://[^"'\s]+\.(?:jpg|jpeg|png|webp)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    if let range = Range(match.range, in: html) {
                        let url = String(html[range])
                        if !url.contains("google.com") && !url.contains("gstatic.com") && !url.contains("googleapis.com") {
                            urls.append(url)
                        }
                    }
                }
            }
        case .baidu:
            // 百度图片搜索结果
            let pattern = #""thumbURL":"(https?://[^"]+)""#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: html) {
                        urls.append(String(html[range]))
                    }
                }
            }
            // 备用
            if urls.isEmpty {
                let altPattern = #"https?://[^"'\s]+\.(?:jpg|jpeg|png)"#
                if let regex = try? NSRegularExpression(pattern: altPattern, options: .caseInsensitive) {
                    let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                    for match in matches {
                        if let range = Range(match.range, in: html) {
                            let url = String(html[range])
                            if !url.contains("bdimg") && !url.contains("baidu.com") && !url.contains("bcebos") {
                                urls.append(url)
                            }
                        }
                    }
                }
            }
        }

        // 去重
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    private func selectImage(_ result: CoverSearchResult) async {
        guard let url = URL(string: result.url) else { return }
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            if data.count > 100 {
                onSelect(data)
                dismiss()
            }
        } catch {
            print("[CoverSearch] Download failed: \(error)")
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
