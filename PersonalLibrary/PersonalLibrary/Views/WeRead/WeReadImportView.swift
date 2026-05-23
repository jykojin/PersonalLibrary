import SwiftUI
import SwiftData

/// 微信读书导入主视图
/// 流程：登录 → 加载书单 → 选择书籍 → 导入
struct WeReadImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingLogin = false
    @State private var isLoggedIn = false
    @State private var isLoading = false
    @State private var items: [WeReadImportItem] = []
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isImporting = false
    @State private var importResult: WeReadService.ImportSummary?
    @State private var showingResult = false
    @State private var filterType: BookTypeFilter = .all

    private let service = WeReadService()

    enum BookTypeFilter: String, CaseIterable {
        case all = "全部"
        case ebook = "电子书"
        case audiobook = "有声书"
    }

    private var filteredItems: [WeReadImportItem] {
        switch filterType {
        case .all: return items
        case .ebook: return items.filter { $0.bookType == .ebook }
        case .audiobook: return items.filter { $0.bookType == .audiobook }
        }
    }

    private var selectedCount: Int {
        items.filter(\.isSelected).count
    }

    private var ebookCount: Int {
        items.filter { $0.bookType == .ebook }.count
    }

    private var audiobookCount: Int {
        items.filter { $0.bookType == .audiobook }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isLoggedIn {
                    loginPromptView
                } else if isLoading {
                    loadingView
                } else if items.isEmpty {
                    emptyView
                } else {
                    bookListView
                }
            }
            .navigationTitle("微信读书导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if !items.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("导入 (\(selectedCount))") {
                            Task { await performImport() }
                        }
                        .disabled(selectedCount == 0 || isImporting)
                    }
                }
            }
            .sheet(isPresented: $showingLogin) {
                WeReadLoginView { cookies in
                    Task {
                        await service.setCookies(cookies)
                        isLoggedIn = true
                        await loadBooks()
                    }
                }
            }
            .alert("导入完成", isPresented: $showingResult) {
                Button("好的") { dismiss() }
            } message: {
                if let result = importResult {
                    Text("成功导入 \(result.imported) 本书" +
                         (result.skipped > 0 ? "\n跳过 \(result.skipped) 本（已存在）" : ""))
                }
            }
            .alert("错误", isPresented: $showingError) {
                Button("好的") {}
                if errorMessage?.contains("过期") == true || errorMessage?.contains("登录") == true {
                    Button("重新登录") {
                        showingLogin = true
                    }
                }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    // MARK: - 子视图

    private var loginPromptView: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.and.wreath")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("导入微信读书书单")
                .font(.title2)
                .fontWeight(.bold)

            Text("使用微信扫码登录微信读书网页版\n即可导入你的电子书和有声书记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Label("电子书将标记为「电子书」类型", systemImage: "ipad")
                Label("有声书将标记为「有声书」类型", systemImage: "headphones")
                Label("不影响你的纸质书记录", systemImage: "book.closed")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                showingLogin = true
            } label: {
                Label("扫码登录", systemImage: "qrcode")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("正在加载书单...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("微信读书书架为空")
                .font(.headline)
            Text("你的微信读书中暂无书籍")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var bookListView: some View {
        VStack(spacing: 0) {
            // 统计与筛选
            VStack(spacing: 8) {
                HStack {
                    Text("共 \(items.count) 本")
                        .font(.subheadline)
                    Spacer()
                    Text("电子书 \(ebookCount)")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("有声书 \(audiobookCount)")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
                .padding(.horizontal)

                // 类型筛选
                Picker("筛选", selection: $filterType) {
                    ForEach(BookTypeFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // 全选/取消全选
                HStack {
                    Button("全选") { toggleAll(selected: true) }
                    Button("取消全选") { toggleAll(selected: false) }
                    Spacer()
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                        Text("导入中...")
                            .font(.caption)
                    }
                }
                .font(.caption)
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            // 书籍列表
            List {
                ForEach(filteredItems) { item in
                    WeReadBookRow(item: item) {
                        toggleSelection(id: item.id)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Actions

    private func loadBooks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            items = try await service.fetchAllBooks()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func performImport() async {
        isImporting = true
        defer { isImporting = false }

        do {
            let result = try await service.importBooks(items, modelContext: modelContext)
            importResult = result
            showingResult = true
        } catch {
            errorMessage = "导入失败: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func toggleAll(selected: Bool) {
        for i in items.indices {
            items[i].isSelected = selected
        }
    }

    private func toggleSelection(id: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isSelected.toggle()
        }
    }
}

// MARK: - Book Row

struct WeReadBookRow: View {
    let item: WeReadImportItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 选择框
            Button(action: onToggle) {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isSelected ? .blue : .gray)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // 封面
            if let coverURL = item.cover, let url = URL(string: coverURL) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .overlay {
                            Image(systemName: bookTypeIcon)
                                .foregroundStyle(.gray)
                        }
                }
                .frame(width: 44, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 44, height: 60)
                    .overlay {
                        Image(systemName: bookTypeIcon)
                            .foregroundStyle(.gray)
                    }
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(item.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // 类型标签
                    Text(item.bookType.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(bookTypeBadgeColor.opacity(0.15))
                        .foregroundStyle(bookTypeBadgeColor)
                        .clipShape(Capsule())

                    // 进度
                    if item.isFinished {
                        Text("已读完")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else if item.progress > 0 {
                        Text("\(item.progress)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // 阅读时长
                    let totalMinutes = (item.readingTime + item.ttsTime) / 60
                    if totalMinutes > 0 {
                        Text(formatDuration(totalMinutes))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var bookTypeIcon: String {
        switch item.bookType {
        case .ebook: return "ipad"
        case .audiobook: return "headphones"
        case .paper: return "book.closed"
        }
    }

    private var bookTypeBadgeColor: Color {
        switch item.bookType {
        case .ebook: return .blue
        case .audiobook: return .purple
        case .paper: return .brown
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return mins > 0 ? "\(hours)h\(mins)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}
