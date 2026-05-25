import Foundation

/// 文件日志工具 — 写入 Documents/logs/ 目录，支持 rotation
/// - 单文件最大 2MB
/// - 保留最近 3 个日志文件
/// - 文件命名: app.log (当前), app.1.log, app.2.log
final class FileLogger: @unchecked Sendable {
    static let shared = FileLogger()

    private let queue = DispatchQueue(label: "com.example.PersonalLibrary.FileLogger")
    private let logDirectory: URL
    private let currentLogURL: URL
    private let maxFileSize: UInt64 = 2 * 1024 * 1024  // 2MB
    private let maxFiles = 3

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        logDirectory = docs.appendingPathComponent("logs", isDirectory: true)

        // 确保目录存在
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        currentLogURL = logDirectory.appendingPathComponent("app.log")

        // 启动时写分隔线
        let separator = "\n--- APP LAUNCH \(Self.dateFormatter.string(from: Date())) ---\n"
        appendToFile(separator)
    }

    func log(_ message: String) {
        let timestamp = Self.timeFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        queue.async { [weak self] in
            self?.appendToFile(line)
            self?.rotateIfNeeded()
        }
    }

    // MARK: - File Access (for export UI)

    /// 返回所有日志文件路径（最新在前）
    var logFiles: [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return []
        }
        return contents
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 当前日志文件大小（字节）
    var currentFileSize: UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: currentLogURL.path) else {
            return 0
        }
        return attrs[.size] as? UInt64 ?? 0
    }

    /// 所有日志文件总大小（字节）
    var totalSize: UInt64 {
        logFiles.reduce(0) { total, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            return total + size
        }
    }

    /// 清空所有日志
    func clearAll() {
        queue.async { [weak self] in
            guard let self else { return }
            for file in self.logFiles {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// 合并所有日志内容（用于导出）
    func mergedContent() -> String {
        var result = ""
        for file in logFiles.reversed() {  // 旧的在前
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                result += content
            }
        }
        return result
    }

    /// 日志目录路径
    var directoryPath: String { logDirectory.path }

    // MARK: - Private

    private func appendToFile(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: currentLogURL.path) {
            if let handle = try? FileHandle(forWritingTo: currentLogURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: currentLogURL)
        }
    }

    private func rotateIfNeeded() {
        guard currentFileSize > maxFileSize else { return }

        let fm = FileManager.default

        // 删除最老的文件
        let oldest = logDirectory.appendingPathComponent("app.\(maxFiles - 1).log")
        try? fm.removeItem(at: oldest)

        // 依次重命名: app.1.log → app.2.log, app.log → app.1.log
        for i in stride(from: maxFiles - 2, through: 1, by: -1) {
            let src = logDirectory.appendingPathComponent("app.\(i).log")
            let dst = logDirectory.appendingPathComponent("app.\(i + 1).log")
            try? fm.moveItem(at: src, to: dst)
        }

        // 当前文件变为 app.1.log
        let archived = logDirectory.appendingPathComponent("app.1.log")
        try? fm.moveItem(at: currentLogURL, to: archived)

        // 创建新的空文件
        let header = "--- ROTATED \(Self.dateFormatter.string(from: Date())) ---\n"
        try? header.data(using: .utf8)?.write(to: currentLogURL)
    }

    // MARK: - Formatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}
