import Foundation

/// 备份信息
struct BackupInfo: Identifiable {
    let id = UUID()
    let url: URL
    let date: Date
    let fileSize: Int64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// 备份错误
enum BackupError: LocalizedError {
    case iCloudUnavailable
    case databaseNotFound
    case backupFailed(String)
    case restoreFailed(String)
    case noBackupSelected

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive 不可用，请确认已登录 iCloud 并开启 iCloud Drive"
        case .databaseNotFound:
            return "找不到数据库文件"
        case .backupFailed(let reason):
            return "备份失败：\(reason)"
        case .restoreFailed(let reason):
            return "恢复失败：\(reason)"
        case .noBackupSelected:
            return "未选择备份文件"
        }
    }
}

/// 数据库备份与恢复服务
/// 将 SwiftData 的 SQLite 数据库文件备份到 iCloud Drive
final class BackupService {
    static let shared = BackupService()

    /// iCloud Drive 中的备份目录名
    private let backupFolderName = "Backups"

    /// 数据库文件名（SwiftData 默认）
    private let dbFileName = "default.store"

    private init() {}

    // MARK: - Public

    /// 创建备份到 iCloud Drive
    func createBackup() async throws -> BackupInfo {
        let iCloudURL = try getICloudBackupDirectory()
        let dbURL = try getDatabaseURL()

        // 生成带时间戳的备份文件名
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupFileName = "PersonalLibrary_\(timestamp).backup"
        let destinationURL = iCloudURL.appendingPathComponent(backupFileName)

        // 使用 NSFileCoordinator 安全复制数据库文件
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var copyError: Error?

        coordinator.coordinate(readingItemAt: dbURL, options: .withoutChanges, error: &coordinatorError) { safeURL in
            do {
                // 复制主数据库文件
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

        // 同时复制 WAL 文件（如果存在）
        let walURL = dbURL.deletingLastPathComponent().appendingPathComponent("\(dbFileName)-wal")
        if FileManager.default.fileExists(atPath: walURL.path) {
            let walDestination = iCloudURL.appendingPathComponent("\(backupFileName)-wal")
            try? FileManager.default.copyItem(at: walURL, to: walDestination)
        }

        // 获取备份文件大小
        let attrs = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let fileSize = attrs[.size] as? Int64 ?? 0

        return BackupInfo(url: destinationURL, date: Date(), fileSize: fileSize)
    }

    /// 从 iCloud Drive 恢复备份
    func restoreBackup(from backupInfo: BackupInfo) async throws {
        let dbURL = try getDatabaseURL()
        let dbDir = dbURL.deletingLastPathComponent()

        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var restoreError: Error?

        coordinator.coordinate(
            writingItemAt: dbURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { safeURL in
            do {
                // 删除现有数据库文件
                let fm = FileManager.default
                let existingFiles = try fm.contentsOfDirectory(at: dbDir, includingPropertiesForKeys: nil)
                for file in existingFiles where file.lastPathComponent.hasPrefix("default.store") {
                    try fm.removeItem(at: file)
                }

                // 复制备份文件到数据库位置
                try fm.copyItem(at: backupInfo.url, to: safeURL)

                // 复制 WAL 文件（如果存在）
                let walSource = backupInfo.url.deletingLastPathComponent()
                    .appendingPathComponent(backupInfo.url.lastPathComponent + "-wal")
                if fm.fileExists(atPath: walSource.path) {
                    let walDest = dbDir.appendingPathComponent("\(self.dbFileName)-wal")
                    try fm.copyItem(at: walSource, to: walDest)
                }
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

    /// 获取所有备份列表
    func listBackups() async throws -> [BackupInfo] {
        let iCloudURL = try getICloudBackupDirectory()

        let fm = FileManager.default

        // 确保 iCloud 文件已下载
        try? fm.startDownloadingUbiquitousItem(at: iCloudURL)

        let contents = try fm.contentsOfDirectory(
            at: iCloudURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var backups: [BackupInfo] = []
        for url in contents where url.lastPathComponent.hasSuffix(".backup") {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let fileSize = attrs?[.size] as? Int64 ?? 0
            let date = attrs?[.modificationDate] as? Date ?? Date()
            backups.append(BackupInfo(url: url, date: date, fileSize: fileSize))
        }

        // 按日期降序
        return backups.sorted { $0.date > $1.date }
    }

    /// 删除备份
    func deleteBackup(_ backup: BackupInfo) throws {
        let fm = FileManager.default
        try fm.removeItem(at: backup.url)

        // 也删除关联的 WAL 文件
        let walURL = backup.url.deletingLastPathComponent()
            .appendingPathComponent(backup.url.lastPathComponent + "-wal")
        try? fm.removeItem(at: walURL)
    }

    // MARK: - Private

    /// 获取 iCloud Drive 备份目录 URL
    private func getICloudBackupDirectory() throws -> URL {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.example.PersonalLibrary"
        ) else {
            throw BackupError.iCloudUnavailable
        }

        let backupDir = containerURL
            .appendingPathComponent("Documents")
            .appendingPathComponent(backupFolderName)

        // 确保目录存在
        if !FileManager.default.fileExists(atPath: backupDir.path) {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        }

        return backupDir
    }

    /// 获取 SwiftData 数据库文件 URL
    private func getDatabaseURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw BackupError.databaseNotFound
        }

        let dbURL = appSupport.appendingPathComponent(dbFileName)

        // SwiftData 可能将文件放在子目录中
        if FileManager.default.fileExists(atPath: dbURL.path) {
            return dbURL
        }

        // 搜索 Application Support 下的 .store 文件
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: appSupport, includingPropertiesForKeys: nil) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.lastPathComponent == dbFileName {
                    return fileURL
                }
            }
        }

        throw BackupError.databaseNotFound
    }
}
