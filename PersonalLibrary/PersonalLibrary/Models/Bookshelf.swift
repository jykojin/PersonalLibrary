import Foundation
import SwiftData

/// 书架模型 — 用于分类管理书籍
@Model
final class Bookshelf {
    var name: String = ""
    var icon: String = "books.vertical"  // SF Symbol name
    var createdDate: Date = Date()
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Book.bookshelf)
    var books: [Book]? = []

    init(name: String, icon: String = "books.vertical", sortOrder: Int = 0) {
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdDate = Date()
    }
}
