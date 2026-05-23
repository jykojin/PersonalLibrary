import Foundation
import SwiftData

/// 标签模型 — 用于给书籍打标签，支持多对多关系
@Model
final class Tag {
    var name: String = ""
    var color: String = "#007AFF"  // 颜色的 hex 值
    var createdDate: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Book.tags)
    var books: [Book]? = []

    init(name: String, color: String = "#007AFF") {
        self.name = name
        self.color = color
        self.createdDate = Date()
    }
}
