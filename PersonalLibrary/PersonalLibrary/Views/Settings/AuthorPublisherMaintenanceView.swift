import SwiftUI
import SwiftData

/// 作者/出版社维护视图
/// 列出所有作者和出版社及其出现次数，支持编辑名字并批量应用到相关图书
struct AuthorPublisherMaintenanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.addedDate, order: .reverse) private var allBooks: [Book]

    @State private var selectedTab = 0  // 0=作者, 1=出版社
    @State private var searchText = ""
    @State private var editingItem: NameCountItem?
    @State private var newName = ""
    @State private var showingEditSheet = false
    @State private var showingResult = false
    @State private var resultMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Tab 切换
            Picker("类型", selection: $selectedTab) {
                Text("作者").tag(0)
                Text("出版社").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 8)

            // 列表
            List {
                ForEach(filteredItems) { item in
                    Button {
                        editingItem = item
                        newName = item.name
                        showingEditSheet = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text("\(item.count) 本")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("作者与出版社")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditSheet) {
            editSheet
        }
        .alert("修改完成", isPresented: $showingResult) {
            Button("好的") {}
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: - Data

    private var authorItems: [NameCountItem] {
        var dict: [String: Int] = [:]
        for book in allBooks where !book.isArchived {
            let authors = book.author.components(separatedBy: ", ")
            for name in authors {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed != "未知作者" {
                    dict[trimmed, default: 0] += 1
                }
            }
        }
        return dict.map { NameCountItem(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var publisherItems: [NameCountItem] {
        var dict: [String: Int] = [:]
        for book in allBooks where !book.isArchived {
            if let p = book.publisher, !p.isEmpty {
                let publishers = p.components(separatedBy: ", ")
                for name in publishers {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        dict[trimmed, default: 0] += 1
                    }
                }
            }
        }
        return dict.map { NameCountItem(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var currentItems: [NameCountItem] {
        selectedTab == 0 ? authorItems : publisherItems
    }

    private var filteredItems: [NameCountItem] {
        if searchText.isEmpty { return currentItems }
        return currentItems.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("当前名称") {
                    Text(editingItem?.name ?? "")
                        .foregroundStyle(.secondary)
                }

                Section("修改为") {
                    TextField("输入新名称", text: $newName)
                }

                if let item = editingItem {
                    Section("影响范围") {
                        Text("将修改 \(item.count) 本书的\(selectedTab == 0 ? "作者" : "出版社")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("编辑\(selectedTab == 0 ? "作者" : "出版社")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingEditSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        applyRename()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty ||
                              newName == editingItem?.name)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func applyRename() {
        guard let item = editingItem else { return }
        let oldName = item.name
        let trimmedNew = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmedNew.isEmpty, trimmedNew != oldName else { return }

        var updatedCount = 0

        if selectedTab == 0 {
            // 作者
            for book in allBooks {
                if book.author == oldName {
                    book.author = trimmedNew
                    updatedCount += 1
                } else if book.author.contains(oldName) {
                    // 多作者情况：替换其中一个
                    let parts = book.author.components(separatedBy: ", ")
                    let newParts = parts.map { $0 == oldName ? trimmedNew : $0 }
                    let joined = newParts.joined(separator: ", ")
                    if joined != book.author {
                        book.author = joined
                        updatedCount += 1
                    }
                }
            }
        } else {
            // 出版社
            for book in allBooks {
                if book.publisher == oldName {
                    book.publisher = trimmedNew
                    updatedCount += 1
                } else if let p = book.publisher, p.contains(oldName) {
                    let parts = p.components(separatedBy: ", ")
                    let newParts = parts.map { $0 == oldName ? trimmedNew : $0 }
                    let joined = newParts.joined(separator: ", ")
                    if joined != p {
                        book.publisher = joined
                        updatedCount += 1
                    }
                }
            }
        }

        if updatedCount > 0 {
            try? modelContext.save()
        }

        showingEditSheet = false
        resultMessage = "已将「\(oldName)」改为「\(trimmedNew)」，更新了 \(updatedCount) 本书"
        showingResult = true
    }
}

// MARK: - Helper Model

struct NameCountItem: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

#Preview {
    NavigationStack {
        AuthorPublisherMaintenanceView()
    }
    .modelContainer(for: [Book.self], inMemory: true)
}
