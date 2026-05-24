import Foundation

/// 文件日志工具 — 把性能日志写入 Documents/perf.log，方便从设备拉取
final class FileLogger: @unchecked Sendable {
    static let shared = FileLogger()

    private let queue = DispatchQueue(label: "com.example.PersonalLibrary.FileLogger")
    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("perf.log")
        // 追加模式：启动时写分隔线，不清空历史
        let separator = "\n--- APP LAUNCH \(Date()) ---\n"
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(separator.data(using: .utf8)!)
                handle.closeFile()
            }
        } else {
            try? separator.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    func log(_ message: String) {
        let timestamp = Self.formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try? data.write(to: self.fileURL)
                }
            }
        }
    }

    /// 日志文件路径（用于 devicectl 拉取）
    var filePath: String { fileURL.path }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
