import SwiftUI

struct ContentView: View {
    /// 启动时数据容器创建失败的错误（非 nil 时弹出安全模式提示）
    var startupError: Error? = nil
    @State private var showStartupAlert = false

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
        .onAppear { if startupError != nil { showStartupAlert = true } }
        .alert("数据加载失败", isPresented: $showStartupAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("无法打开本地数据库，已进入临时安全模式——此模式下的改动不会保存。请重启 App 重试；若反复出现，建议先在「更多 → 数据备份」导出数据，或重装 App 后从备份恢复。")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Book.self, ReadingRecord.self, Bookshelf.self, Tag.self], inMemory: true)
}
