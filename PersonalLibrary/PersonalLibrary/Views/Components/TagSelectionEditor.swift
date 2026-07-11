import SwiftUI
import SwiftData

/// 统一的标签选择编辑器:输入即过滤已有标签、可点选加入、无匹配时创建。
/// 只维护 `selectedTags`(标签名集合),不做持久化 —— 由宿主提交。
/// 使用方式:放进宿主的一个 Section 里,例如 `Section("标签") { TagSelectionEditor(selectedTags: $selectedTags) }`。
struct TagSelectionEditor: View {
    @Binding var selectedTags: Set<String>
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var searchText = ""

    var body: some View {
        // 已选标签
        if !selectedTags.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(Array(selectedTags).sorted(), id: \.self) { tagName in
                    TagChip(name: tagName, isSelected: true) {
                        selectedTags.remove(tagName)
                    }
                }
            }
            .padding(.vertical, 4)
        }

        // 搜索框
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索或创建标签", text: $searchText)
        }

        // 搜索结果 / 创建按钮
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let matched = allTags.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                && !selectedTags.contains($0.name)
            }
            if matched.isEmpty {
                Button {
                    selectedTags.insert(trimmed)
                    searchText = ""
                } label: {
                    Label("创建「\(trimmed)」", systemImage: "plus.circle")
                }
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(matched) { tag in
                        TagChip(name: tag.name, isSelected: false) {
                            selectedTags.insert(tag.name)
                            searchText = ""
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
