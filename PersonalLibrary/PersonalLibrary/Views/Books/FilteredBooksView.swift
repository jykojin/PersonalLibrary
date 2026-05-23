import SwiftUI
import SwiftData

/// 通用的筛选书籍列表视图
/// 用于从统计页点击作者/出版社/标签/评分后展示对应书籍
struct FilteredBooksView: View {
    let title: String
    let books: [Book]

    var body: some View {
        List {
            ForEach(books) { book in
                NavigationLink(destination: BookDetailView(book: book)) {
                    BookRowView(book: book)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if books.isEmpty {
                ContentUnavailableView("暂无书籍", systemImage: "book.closed")
            }
        }
    }
}
