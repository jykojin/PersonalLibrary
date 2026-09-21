import UIKit

@MainActor
protocol EnrichmentBackgroundTaskManaging: AnyObject {
    func beginTask(
        named name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier

    func endTask(_ identifier: UIBackgroundTaskIdentifier)
}

@MainActor
final class SystemEnrichmentBackgroundTaskManager: EnrichmentBackgroundTaskManaging {
    static let shared = SystemEnrichmentBackgroundTaskManager()

    private init() {}

    func beginTask(
        named name: String,
        expirationHandler: @escaping @MainActor @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(
            withName: name,
            expirationHandler: expirationHandler
        )
    }

    func endTask(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

@MainActor
private final class EnrichmentBackgroundTaskLease {
    private let taskManager: any EnrichmentBackgroundTaskManaging
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String, taskManager: any EnrichmentBackgroundTaskManaging) {
        self.taskManager = taskManager
        identifier = taskManager.beginTask(named: name) { [weak self] in
            // Expiration means iOS is about to suspend the app. Release the OS
            // assertion, but leave the Swift task alive so it can resume when
            // the app returns to the foreground.
            self?.finish()
        }
    }

    func finish() {
        guard identifier != .invalid else { return }
        let identifierToEnd = identifier
        identifier = .invalid
        taskManager.endTask(identifierToEnd)
    }
}

@MainActor
struct EnrichmentBackgroundExecution {
    private let taskManager: any EnrichmentBackgroundTaskManaging

    init(
        taskManager: (any EnrichmentBackgroundTaskManaging)? = nil
    ) {
        self.taskManager = taskManager ?? SystemEnrichmentBackgroundTaskManager.shared
    }

    func run<Result>(
        named name: String,
        operation: () async -> Result
    ) async -> Result {
        let lease = EnrichmentBackgroundTaskLease(name: name, taskManager: taskManager)
        defer { lease.finish() }
        return await operation()
    }
}
