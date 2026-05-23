import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            BookListView()
                .tabItem {
                    Label("藏书", systemImage: "books.vertical")
                }

            BookshelfListView()
                .tabItem {
                    Label("书架", systemImage: "square.stack.3d.up")
                }

            StatisticsView()
                .tabItem {
                    Label("统计", systemImage: "chart.bar")
                }

            NavigationStack {
                ImportExportView()
            }
            .tabItem {
                Label("更多", systemImage: "ellipsis.circle")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Book.self, ReadingRecord.self, Bookshelf.self, Tag.self], inMemory: true)
}
