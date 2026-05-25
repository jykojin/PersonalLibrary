import Foundation

/// 统一日志系统 — 所有模块通过此入口记录日志
/// - DEBUG: 控制台 + 文件（全级别）
/// - Release: 仅 warning/error 写文件
enum AppLogger {

    // MARK: - Log Levels

    enum Level: Int, Comparable, Sendable {
        case debug = 0    // 开发调试，Release 不输出
        case info = 1     // 正常流程关键节点
        case warning = 2  // 潜在问题，但不影响功能
        case error = 3    // 功能异常

        var prefix: String {
            switch self {
            case .debug:   return "DEBUG"
            case .info:    return "INFO"
            case .warning: return "WARN"
            case .error:   return "ERROR"
            }
        }

        static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Public API

    /// 记录日志
    /// - Parameters:
    ///   - message: 日志内容
    ///   - level: 日志级别（默认 .info）
    ///   - category: 分类标签（如 "Migration", "CoverFetch", "WeReadSync"）
    static func log(_ message: String, level: Level = .info, category: String = "General") {
        let formatted = "[\(category)] \(message)"

        #if DEBUG
        // DEBUG: 全部输出到控制台
        print("[\(level.prefix)] \(formatted)")
        // DEBUG: 全级别写文件（方便从设备拉取分析）
        FileLogger.shared.log("[\(level.prefix)] \(formatted)")
        #else
        // Release: 只有 warning/error 写文件
        if level >= .warning {
            FileLogger.shared.log("[\(level.prefix)] \(formatted)")
        }
        #endif
    }

    // MARK: - Convenience

    static func debug(_ message: String, category: String = "General") {
        log(message, level: .debug, category: category)
    }

    static func info(_ message: String, category: String = "General") {
        log(message, level: .info, category: category)
    }

    static func warning(_ message: String, category: String = "General") {
        log(message, level: .warning, category: category)
    }

    static func error(_ message: String, category: String = "General") {
        log(message, level: .error, category: category)
    }

    // MARK: - Performance logging (直写文件，用于高频性能记录)

    /// 性能日志 — 直写文件，不经过级别过滤（用于批量操作的逐条计时）
    static func perf(_ message: String, category: String = "Perf") {
        let formatted = "[PERF][\(category)] \(message)"
        #if DEBUG
        print(formatted)
        #endif
        FileLogger.shared.log(formatted)
    }
}
