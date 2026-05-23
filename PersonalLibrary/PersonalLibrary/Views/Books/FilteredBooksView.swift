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
                    FilteredBookRow(book: book)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if books.isEmpty {
                ContentUnavailableView("暂无书籍", systemImage: "book.closed")
            }
        }
    }
}

private struct FilteredBookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            // 封面缩略图
            if let data = book.coverImageData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 56)
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 状态标签
            Text(book.status.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor(book.status).opacity(0.1))
                .foregroundStyle(statusColor(book.status))
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }

    private func statusColor(_ status: ReadingStatus) -> Color {
        switch status {
        case .reading: return .orange
        case .finished: return .green
        case .wishlist: return .blue
        case .dropped: return .red
        case .idle: return .gray
        }
    }
}
