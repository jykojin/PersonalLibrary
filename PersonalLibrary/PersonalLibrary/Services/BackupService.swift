import Foundation

/// 备份信息
struct BackupInfo: Identifiable {
    let id = UUID()
    let url: URL
    let date: Date
    let fileSize: Int64

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }
}

/// 备份错误
enum BackupError: LocalizedError {
    case databaseNotFound
    case backupFailed(String)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "找不到数据库文件"
        case .backupFailed(let reason):
            return "备份失败：\(reason)"
        case .restoreFailed(let reason):
            return "恢复失败：\(reason)"
        }
    }
}

/// 数据库备份与恢复服务
/// 备份：复制数据库到本地备份目录，通过分享面板让用户存到 iCloud Drive / Files
/// 恢复：通过文件选择器从任意位置导入备份文件
final class BackupService {
    static let shared = BackupService()

    /// 数据库文件名（与 ModelConfiguration name 一致）
    private let dbFileName = "PersonalLibrary.store"

    private init() {}

    // MARK: - Public

    /// 创建备份，返回备份文件 URL（用于分享面板）
    func createBackup() async throws -> BackupInfo {
        let dbURL = try getDatabaseURL()
        let backupDir = getLocalBackupDirectory()

        // 生成带时间戳的备份文件名
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupFileName = "PersonalLibrary_\(timestamp).plbackup"
        let destinationURL = backupDir.appendingPathComponent(backupFileName)

        // 使用 NSFileCoordinator 安全复制数据库文件
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var copyError: Error?

        coordinator.coordinate(readingItemAt: dbURL, options: .withoutChanges, error: &coordinatorError) { safeURL in
            do {
                try FileManager.default.copyItem(at: safeURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        if let error = coordinatorError {
            throw BackupError.backupFailed(error.localizedDescription)
        }
        if let error = copyError {
            throw BackupError.backupFailed(error.localizedDescription)
        }

        // 同时复制 WAL 文件（如果存在），合并到主备份中
        let walURL = dbURL.deletingLastPathComponent().appendingPathComponent("\(dbFileName)-wal")
        if FileManager.default.fileExists(atPath: walURL.path) {
            let walDest = backupDir.appendingPathComponent("\(backupFileName)-wal")
            try? FileManager.default.copyItem(at: walURL, to: walDest)
        }

        // 获取备份文件大小
        let attrs = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let fileSize = attrs[.size] as? Int64 ?? 0

        return BackupInfo(url: destinationURL, date: Date(), fileSize: fileSize)
    }

    /// 从备份文件恢复数据库
    func restoreBackup(from sourceURL: URL) async throws {
        let dbURL = try getDatabaseURL()
        let dbDir = dbURL.deletingLastPathComponent()

        // 确保有权限访问文件
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw BackupError.restoreFailed("无法访问备份文件")
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var restoreError: Error?

        coordinator.coordinate(
            writingItemAt: dbURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { safeURL in
            do {
                let fm = FileManager.default

                // 删除现有数据库文件
                let existingFiles = try fm.contentsOfDirectory(at: dbDir, includingPropertiesForKeys: nil)
                for file in existingFiles where file.lastPathComponent.hasPrefix("PersonalLibrary.store") {
                    try fm.removeItem(at: file)
                }

                // 复制备份文件到数据库位置
                try fm.copyItem(at: sourceURL, to: safeURL)
            } catch {
                restoreError = error
            }
        }

        if let error = coordinatorError {
            throw BackupError.restoreFailed(error.localizedDescription)
        }
        if let error = restoreError {
            throw BackupError.restoreFailed(error.localizedDescription)
        }
    }

    /// 获取本地备份列表
    func listLocalBackups() -> [BackupInfo] {
        let backupDir = getLocalBackupDirectory()
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var backups: [BackupInfo] = []
        for url in contents where url.pathExtension == "plbackup" {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let fileSize = attrs?[.size] as? Int64 ?? 0
            let date = attrs?[.modificationDate] as? Date ?? Date()
            backups.append(BackupInfo(url: url, date: date, fileSize: fileSize))
        }

        return backups.sorted { $0.date > $1.date }
    }

    /// 删除本地备份
    func deleteBackup(_ backup: BackupInfo) throws {
        try FileManager.default.removeItem(at: backup.url)

        // 也删除关联的 WAL 文件
        let walURL = backup.url.deletingLastPathComponent()
            .appendingPathComponent(backup.url.lastPathComponent + "-wal")
        try? FileManager.default.removeItem(at: walURL)
    }

    // MARK: - Private

    /// 获取本地备份目录
    private func getLocalBackupDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupDir = docs.appendingPathComponent("Backups")

        if !FileManager.default.fileExists(atPath: backupDir.path) {
            try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        }

        return backupDir
    }

    /// 获取 SwiftData 数据库文件 URL
    private func getDatabaseURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw BackupError.databaseNotFound
        }

        let fm = FileManager.default

        // 直接路径
        let dbURL = appSupport.appendingPathComponent(dbFileName)
        if fm.fileExists(atPath: dbURL.path) {
            return dbURL
        }

        // 也检查 default.store（SwiftData 默认名）
        let defaultURL = appSupport.appendingPathComponent("default.store")
        if fm.fileExists(atPath: defaultURL.path) {
            return defaultURL
        }

        // 递归搜索 Application Support 下的 .store 文件
        if let enumerator = fm.enumerator(at: appSupport, includingPropertiesForKeys: nil) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "store" {
                    return fileURL
                }
            }
        }

        throw BackupError.databaseNotFound
    }
}
