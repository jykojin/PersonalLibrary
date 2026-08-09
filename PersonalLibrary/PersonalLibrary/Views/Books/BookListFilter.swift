import Foundation

/// 首页藏书列表的筛选逻辑（纯函数，便于单测）。
/// 书架分支仍留在 `BookListView`（依赖 `Bookshelf` 反向关系），此处只负责
/// 「范围 → 纸质书筛选 → 文字匹配」这条主链路。
enum BookListFilter {

    /// 按范围取基准集合。
    /// - Parameter archivedScope: true = 只看已取消收藏的书；false = 排除它们。
    static func scopedBooks(_ books: [Book], archivedScope: Bool) -> [Book] {
        books.filter { archivedScope ? $0.isArchived : !$0.isArchived }
    }

    /// 单本书是否匹配文字查询。
    static func matches(book: Book, query: String, scope: SearchScope) -> Bool {
        switch scope {
        case .all:
            if book.title.localizedCaseInsensitiveContains(query) { return true }
            if book.author.localizedCaseInsensitiveContains(query) { return true }
            if book.publisher?.localizedCaseInsensitiveContains(query) == true { return true }
            if book.isbn?.localizedCaseInsensitiveContains(query) == true { return true }
            if book.bookshelf?.name.localizedCaseInsensitiveContains(query) == true { return true }
            if book.tags?.contains(where: { $0.name.localizedCaseInsensitiveContains(query) }) == true { return true }
            if book.translator?.localizedCaseInsensitiveContains(query) == true { return true }
            return false
        case .title:
            return book.title.localizedCaseInsensitiveContains(query)
        case .author:
            return book.author.localizedCaseInsensitiveContains(query)
        case .tag:
            return book.tags?.contains(where: { $0.name.localizedCaseInsensitiveContains(query) }) == true
        case .publisher:
            return book.publisher?.localizedCaseInsensitiveContains(query) == true
        case .shelf:
            return book.bookshelf?.name.localizedCaseInsensitiveContains(query) == true
        }
    }

    /// 完整链路：范围 → 纸质书筛选 → 文字匹配。
    static func apply(
        books: [Book],
        archivedScope: Bool,
        paperOnly: Bool,
        searchText: String,
        searchScope: SearchScope
    ) -> [Book] {
        var result = scopedBooks(books, archivedScope: archivedScope)

        if paperOnly {
            result = result.filter { $0.bookType == .paper }
        }

        if !searchText.isEmpty {
            result = result.filter { matches(book: $0, query: searchText, scope: searchScope) }
        }

        return result
    }
}
