import Foundation

/// 统一日志系统 — 所有模块通过此入口记录日志
/// - 支持运行时三档切换：详细 / 正常 / 关闭
/// - DEBUG 构建额外输出到控制台
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

    // MARK: - Runtime Log Mode

    /// 运行时日志模式 — 用户可在设置中切换
    enum Mode: Int, CaseIterable, Sendable {
        case verbose = 0  // 全部输出（debug + info + warning + error + perf）
        case normal = 1   // 仅 warning + error（默认）
        case off = 2      // 完全关闭

        var displayName: String {
            switch self {
            case .verbose: return "详细"
            case .normal:  return "正常"
            case .off:     return "关闭"
            }
        }

        var description: String {
            switch self {
            case .verbose: return "记录全部日志（调试用）"
            case .normal:  return "仅记录警告和错误"
            case .off:     return "不记录任何日志"
            }
        }
    }

    private static let modeKey = "AppLogger_mode"

    /// 当前日志模式
    static var currentMode: Mode {
        get {
            Mode(rawValue: UserDefaults.standard.integer(forKey: modeKey)) ?? .normal
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
        }
    }

    // MARK: - Public API

    /// 记录日志
    /// - Parameters:
    ///   - message: 日志内容
    ///   - level: 日志级别（默认 .info）
    ///   - category: 分类标签（如 "Migration", "CoverFetch", "WeReadSync"）
    static func log(_ message: String, level: Level = .info, category: String = "General") {
        let mode = currentMode
        guard mode != .off else { return }

        // normal 模式只记录 warning+
        if mode == .normal && level < .warning { return }

        let formatted = "[\(category)] \(message)"

        #if DEBUG
        print("[\(level.prefix)] \(formatted)")
        #endif
        FileLogger.shared.log("[\(level.prefix)] \(formatted)")
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

    // MARK: - Performance logging

    /// 性能日志 — 仅在 verbose 模式下记录
    static func perf(_ message: String, category: String = "Perf") {
        guard currentMode == .verbose else { return }
        let formatted = "[PERF][\(category)] \(message)"
        #if DEBUG
        print(formatted)
        #endif
        FileLogger.shared.log(formatted)
    }
}
