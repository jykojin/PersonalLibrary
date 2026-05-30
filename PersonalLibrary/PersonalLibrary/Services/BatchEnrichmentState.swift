import Foundation

/// 全局批量补全状态指示器
/// 用于让 BackgroundCover 等并行任务在批量补全期间礼让，避免多路并发导致手机过热
actor BatchEnrichmentState {
    static let shared = BatchEnrichmentState()
    private var isRunning = false

    func start() { isRunning = true }
    func stop() { isRunning = false }
    func current() -> Bool { isRunning }
}
