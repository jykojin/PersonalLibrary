import SwiftUI
import SwiftData

@main
struct PersonalLibraryApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try StorageManager.shared.createModelContainer()
        } catch {
            fatalError("无法创建数据容器: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // 处理微信 OAuth 回调
                    WeChatAuthManager.shared.handleOpenURL(url)
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                triggerAutoSyncIfNeeded()
            }
        }
    }

    /// App 回到前台时检查是否需要自动同步微信读书
    @MainActor
    private func triggerAutoSyncIfNeeded() {
        guard WeReadSyncService.shouldAutoSync() else { return }

        let context = modelContainer.mainContext
        let syncService = WeReadSyncService()

        Task {
            let result = await syncService.sync(modelContext: context)
            if result.hasChanges {
                print("[WeReadSync] 自动同步完成: \(result.summary)")
            }
        }
    }
}
