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
        let schema = Schema([Book.self, ReadingRecord.self, Bookshelf.self, Tag.self, ImportRecord.self])

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
}
