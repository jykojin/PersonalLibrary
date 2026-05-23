import SwiftUI
import SwiftData

struct ReadingProgressView: View {
    @Query private var allBooks: [Book]

    private var readingBooks: [Book] {
        allBooks.filter { $0.status == .reading }
    }

    var body: some View {
        NavigationStack {
            List {
                if readingBooks.isEmpty {
                    ContentUnavailableView(
                        "没有在读的书",
                        systemImage: "book",
                        description: Text("去书架把一本书的状态改为「在读」")
                    )
                } else {
                    ForEach(readingBooks) { book in
                        NavigationLink(destination: BookDetailView(book: book)) {
                            ReadingBookRow(book: book)
                        }
                    }
                }
            }
            .navigationTitle("正在阅读")
        }
    }
}

struct ReadingBookRow: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(book.title)
                    .font(.headline)
                Spacer()
                Text("\(Int(book.progress * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: book.progress)
                .tint(.blue)

            Text("\(book.currentPage) / \(book.totalPages) 页")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ReadingProgressView()
        .modelContainer(for: [Book.self, ReadingRecord.self], inMemory: true)
}
