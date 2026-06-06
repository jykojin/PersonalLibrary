import Foundation
import SwiftData

/// 存储位置选项
enum StorageLocation: String, CaseIterable {
    case icloud = "iCloud"
    case local = "本地"

    var description: String {
        switch self {
        case .icloud: return "iCloud（多设备同步）"
        case .local: return "仅本机存储"
        }
    }

    var icon: String {
        switch self {
        case .icloud: return "icloud"
        case .local: return "iphone"
        }
    }
}

/// 存储管理器 — 管理数据存储位置配置
/// SwiftData 的 ModelContainer 在初始化后不可更改存储位置，
/// 切换存储位置需要重启 app 才能生效。
final class StorageManager {
    static let shared = StorageManager()

    private let storageLocationKey = "StorageLocation"

    private init() {}

    /// 当前存储位置设置
    var currentLocation: StorageLocation {
        get {
            let rawValue = UserDefaults.standard.string(forKey: storageLocationKey) ?? StorageLocation.icloud.rawValue
            return StorageLocation(rawValue: rawValue) ?? .icloud
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageLocationKey)
        }
    }

    /// 创建对应存储位置的 ModelContainer
    /// 如果 iCloud 模式失败（如模拟器无 iCloud 账号），自动降级为本地存储
    func createModelContainer() throws -> ModelContainer {
        let schema = Schema([Book.self, ReadingRecord.self, Bookshelf.self, Tag.self, ImportRecord.self, SyncHistoryRecord.self])

        if currentLocation == .icloud {
            // 尝试 iCloud 模式
            do {
                let config = ModelConfiguration(
                    "PersonalLibrary",
                    schema: schema,
                    cloudKitDatabase: .automatic
                )
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                // iCloud 不可用，降级为本地存储
                print("⚠️ iCloud 存储不可用，降级为本地存储: \(error.localizedDescription)")
                let localConfig = ModelConfiguration(
                    "PersonalLibrary",
                    schema: schema,
                    cloudKitDatabase: .none
                )
                return try ModelContainer(for: schema, configurations: [localConfig])
            }
        } else {
            let config = ModelConfiguration(
                "PersonalLibrary",
                schema: schema,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [config])
        }
    }

    /// 启动用：创建主容器，失败时降级为内存兜底容器并带回错误（避免 app 启动闪退）。
    /// - 正常：返回真实容器，startupError 为 nil。
    /// - 失败（库损坏/磁盘满/迁移失败）：返回内存容器让 app 仍能启动进入"安全模式"，由 UI 提示用户。
    /// `primary` 注入工厂便于单测强制失败路径。
    static func makeContainerOrFallback(
        primary: () throws -> ModelContainer = { try StorageManager.shared.createModelContainer() }
    ) -> (container: ModelContainer, startupError: Error?) {
        do {
            return (try primary(), nil)
        } catch {
            AppLogger.error("主数据容器创建失败，降级为内存安全模式: \(error)", category: "Storage")
            let schema = Schema([Book.self, ReadingRecord.self, Bookshelf.self, Tag.self, ImportRecord.self, SyncHistoryRecord.self])
            let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // 内存容器创建若再失败，已无可恢复手段，此处保留 fatalError 作为最后兜底
            let fallback = try! ModelContainer(for: schema, configurations: [memConfig])
            return (fallback, error)
        }
    }

    /// 一次性把历史超大/损坏的内联封面压成缩略图：缩小数据库、消除主线程 save 卡顿与看门狗崩溃。
    /// 后台分批执行，每批用独立 context 限制内存峰值；完成后置标志位，不再重复。
    func migrateOversizedCoversIfNeeded(_ container: ModelContainer) {
        let doneKey = "coverThumbnailMigration.v1.done"
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        Task.detached(priority: .utility) {
            let batchSize = 100
            var offset = 0
            var optimized = 0
            while !Task.isCancelled {
                let ctx = ModelContext(container)
                ctx.autosaveEnabled = false
                var descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.addedDate)])
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = offset
                guard let batch = try? ctx.fetch(descriptor), !batch.isEmpty else { break }
                for book in batch {
                    autoreleasepool {
                        guard let data = book.coverImageData else { return }
                        if data.count < 1024 {
                            book.coverImageData = nil  // 38字节坏占位 → 清空，后续按需重抓自愈
                            optimized += 1
                        } else if data.count > CoverImageProcessor.passthroughBelowBytes {
                            let thumb = CoverImageProcessor.thumbnailData(from: data)
                            if thumb.count < data.count {
                                book.coverImageData = thumb
                                optimized += 1
                            }
                        }
                    }
                }
                try? ctx.save()
                offset += batchSize
            }
            UserDefaults.standard.set(true, forKey: doneKey)
            AppLogger.info("封面缩略图迁移完成：优化 \(optimized) 本", category: "Storage")
        }
    }
}
