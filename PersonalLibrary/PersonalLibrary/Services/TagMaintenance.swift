import Foundation
import SwiftData

/// 标签维护工具 — 合并同名重复标签。
enum TagMaintenance {

    /// 合并同名（trim 后）重复标签。
    /// 每组保留 `createdDate` 最早者作为 canonical，规范化其名称为 trim 后的形式，
    /// 把重复标签上的书籍重新指向 canonical（去重避免同一本书重复引用），删除多余标签。
    /// - Returns: 被删除（合并掉）的标签数量。
    @discardableResult
    static func mergeDuplicateTags(in context: ModelContext) -> Int {
        guard let allTags = try? context.fetch(FetchDescriptor<Tag>()) else { return 0 }

        // 按 trim 后名字分组
        var groups: [String: [Tag]] = [:]
        for tag in allTags {
            let key = tag.name.trimmingCharacters(in: .whitespaces)
            groups[key, default: []].append(tag)
        }

        var removed = 0
        var changed = false
        for (trimmedName, tags) in groups {
            // 组内按创建时间升序，最早的作为 canonical
            let sorted = tags.sorted { $0.createdDate < $1.createdDate }
            guard let canonical = sorted.first else { continue }

            // 规范化 canonical 名称（去掉可能的尾随/前导空格）
            if canonical.name != trimmedName {
                canonical.name = trimmedName
                changed = true
            }

            // 组内只有一个就无需合并
            guard sorted.count > 1 else { continue }

            for dup in sorted.dropFirst() {
                for book in dup.books ?? [] {
                    var bookTags = book.tags ?? []
                    bookTags.removeAll { $0.persistentModelID == dup.persistentModelID }
                    if !bookTags.contains(where: { $0.persistentModelID == canonical.persistentModelID }) {
                        bookTags.append(canonical)
                    }
                    book.tags = bookTags
                }
                context.delete(dup)
                removed += 1
                changed = true
            }
        }

        if changed {
            try? context.save()
        }
        return removed
    }
}
