import Foundation
import AoxiangCore

/// A platform-neutral description of the two iOS scheduling policies. The
/// scheduler core uses this value instead of constructing BackgroundTasks
/// requests directly, which keeps registration/submission testable off-device.
public enum IOSBackgroundTaskKind: Equatable {
    case appRefresh
    case processing
}

public struct IOSBackgroundTaskRequest: Equatable {
    public let kind: IOSBackgroundTaskKind
    public let identifier: String
    public let earliestBeginDate: Date
    public let requiresNetworkConnectivity: Bool
    public let requiresExternalPower: Bool

    public init(
        kind: IOSBackgroundTaskKind,
        identifier: String,
        earliestBeginDate: Date,
        requiresNetworkConnectivity: Bool = false,
        requiresExternalPower: Bool = false
    ) {
        self.kind = kind
        self.identifier = identifier
        self.earliestBeginDate = earliestBeginDate
        self.requiresNetworkConnectivity = requiresNetworkConnectivity
        self.requiresExternalPower = requiresExternalPower
    }
}

/// The smallest task surface needed by the coordinator. BGTask conforms to
/// this protocol in the iOS adapter below; tests can use a simple fake task.
public protocol IOSBackgroundTaskExecution: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

public protocol IOSBackgroundTaskSchedulingPort {
    @discardableResult
    func register(
        forTaskWithIdentifier identifier: String,
        handler: @escaping (IOSBackgroundTaskExecution) -> Void
    ) -> Bool

    func submit(_ request: IOSBackgroundTaskRequest) throws
}

public protocol IOSNotificationAuthorizationPort {
    func requestAuthorization(completion: ((Bool) -> Void)?)
}

private struct UnavailableBackgroundTaskSchedulingPort: IOSBackgroundTaskSchedulingPort {
    @discardableResult
    func register(
        forTaskWithIdentifier identifier: String,
        handler: @escaping (IOSBackgroundTaskExecution) -> Void
    ) -> Bool { false }

    func submit(_ request: IOSBackgroundTaskRequest) throws {
        throw IOSBackgroundTaskError.unavailable
    }
}

private struct UnavailableNotificationAuthorizationPort: IOSNotificationAuthorizationPort {
    func requestAuthorization(completion: ((Bool) -> Void)?) { completion?(false) }
}

public enum IOSBackgroundTaskError: Error, Equatable {
    case unavailable
}

extension IOSBackgroundTaskError: LocalizedError {
    public var errorDescription: String? {
        switch self { case .unavailable: return "BackgroundTasks is unavailable on this platform" }
    }
}

public enum IOSBackgroundRegistrationResult: Equatable {
    case registered
    case partiallyRegistered(failedIdentifiers: [String])

    public var allRegistered: Bool {
        if case .registered = self { return true }
        return false
    }
}

public enum IOSBackgroundScheduleResult: Equatable {
    case submitted
    case notRegistered
    case rejected(String)
}

public protocol IOSBackgroundRunnerFactory {
    func makeRunner() -> BackgroundSyncRunner
    func currentAuthentication() -> AuthenticationState
}

/// Closure-backed injection point for the real authenticated collector. The
/// default app uses a fail-closed factory until a visible login session is
/// provided by the caller.
public final class ClosureIOSBackgroundRunnerFactory: IOSBackgroundRunnerFactory {
    private let authentication: () -> AuthenticationState
    private let runner: () -> BackgroundSyncRunner

    public init(
        authentication: @escaping () -> AuthenticationState,
        runner: @escaping () -> BackgroundSyncRunner
    ) {
        self.authentication = authentication
        self.runner = runner
    }

    public func makeRunner() -> BackgroundSyncRunner { runner() }
    public func currentAuthentication() -> AuthenticationState { authentication() }
}

/// No credentials, cookies, or hidden WebViews are created by this fallback.
/// It prevents a production build that forgot to inject a collector from
/// reporting a successful background sync.
public struct UnconfiguredIOSBackgroundRunner: BackgroundSyncRunner {
    public init() {}

    public func run(
        request: BackgroundSyncRequest,
        isCancelled: @escaping () -> Bool
    ) -> BackgroundSyncOutcome {
        isCancelled() ? .cancelled : .needsUserAttention(.collectionNotReady)
    }
}

public struct UnconfiguredIOSBackgroundRunnerFactory: IOSBackgroundRunnerFactory {
    public init() {}
    public func makeRunner() -> BackgroundSyncRunner { UnconfiguredIOSBackgroundRunner() }
    public func currentAuthentication() -> AuthenticationState { .needsLogin }
}

/// Registers and executes best-effort tasks. The system scheduler only stores
/// this object through the app lifecycle; it never creates a hidden WebView.
public final class IOSBackgroundTaskScheduler {
    public let refreshIdentifier: String
    public let processingIdentifier: String

    private let coordinator: BackgroundSyncCoordinator
    private let runnerFactory: IOSBackgroundRunnerFactory
    private let schedulingPort: IOSBackgroundTaskSchedulingPort
    private let notificationAuthorization: IOSNotificationAuthorizationPort
    private let now: () -> Date
    private let registrationLock = NSLock()
    private var registeredIdentifiers: Set<String> = []

    public init(
        refreshIdentifier: String = "cn.nwpu.aoxiang.refresh",
        processingIdentifier: String = "cn.nwpu.aoxiang.processing",
        coordinator: BackgroundSyncCoordinator,
        runnerFactory: IOSBackgroundRunnerFactory,
        schedulingPort: IOSBackgroundTaskSchedulingPort? = nil,
        notificationAuthorization: IOSNotificationAuthorizationPort? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.refreshIdentifier = refreshIdentifier
        self.processingIdentifier = processingIdentifier
        self.coordinator = coordinator
        self.runnerFactory = runnerFactory
        self.schedulingPort = schedulingPort ?? UnavailableBackgroundTaskSchedulingPort()
        self.notificationAuthorization = notificationAuthorization ?? UnavailableNotificationAuthorizationPort()
        self.now = now
    }

    /// Registers each identifier at most once for this scheduler instance. A
    /// failed registration is left unmarked so a later lifecycle hook can
    /// retry only the missing identifier.
    @discardableResult
    public func register() -> IOSBackgroundRegistrationResult {
        var failed: [String] = []
        register(identifier: refreshIdentifier, kind: .appRefresh, failed: &failed)
        register(identifier: processingIdentifier, kind: .processing, failed: &failed)
        return failed.isEmpty ? .registered : .partiallyRegistered(failedIdentifiers: failed)
    }

    /// Requests permission through the injected notification port. The Bool
    /// means the request was dispatched, not that the user granted permission.
    @discardableResult
    public func requestNotificationAuthorization(completion: ((Bool) -> Void)? = nil) -> Bool {
        notificationAuthorization.requestAuthorization(completion: completion)
        return true
    }

    @discardableResult
    public func scheduleAppRefresh(after interval: TimeInterval = 15 * 60) -> IOSBackgroundScheduleResult {
        schedule(IOSBackgroundTaskRequest(
            kind: .appRefresh,
            identifier: refreshIdentifier,
            earliestBeginDate: now().addingTimeInterval(max(0, interval))
        ))
    }

    @discardableResult
    public func scheduleProcessing(after interval: TimeInterval = 60 * 60) -> IOSBackgroundScheduleResult {
        schedule(IOSBackgroundTaskRequest(
            kind: .processing,
            identifier: processingIdentifier,
            earliestBeginDate: now().addingTimeInterval(max(0, interval)),
            requiresNetworkConnectivity: true,
            requiresExternalPower: false
        ))
    }

    private func register(
        identifier: String,
        kind: BackgroundTaskKind,
        failed: inout [String]
    ) {
        registrationLock.lock()
        defer { registrationLock.unlock() }
        guard !registeredIdentifiers.contains(identifier) else { return }
        let didRegister = schedulingPort.register(
            forTaskWithIdentifier: identifier,
            handler: { [weak self] task in
                self?.handle(task, kind: kind)
            }
        )
        if didRegister {
            registeredIdentifiers.insert(identifier)
        } else {
            failed.append(identifier)
        }
    }

    private func schedule(_ request: IOSBackgroundTaskRequest) -> IOSBackgroundScheduleResult {
        registrationLock.lock()
        let isRegistered = registeredIdentifiers.contains(request.identifier)
        registrationLock.unlock()
        guard isRegistered else { return .notRegistered }
        do {
            try schedulingPort.submit(request)
            return .submitted
        } catch {
            // A rejected scheduling hint does not replace the last successful
            // widget snapshot or claim that data collection succeeded.
            return .rejected(error.localizedDescription)
        }
    }

    private func handle(_ task: IOSBackgroundTaskExecution, kind: BackgroundTaskKind) {
        let cancellation = CancellationBox()
        task.expirationHandler = { cancellation.cancel() }
        let request = BackgroundSyncRequest(
            kind: kind,
            requestedAtEpochMilliseconds: Int64(now().timeIntervalSince1970 * 1000)
        )
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            let outcome: BackgroundSyncOutcome
            do {
                outcome = try self.coordinator.run(
                    request: request,
                    runner: self.runnerFactory.makeRunner(),
                    isCancelled: { cancellation.isCancelled }
                )
            } catch {
                task.setTaskCompleted(success: false)
                return
            }
            switch outcome {
            case .success:
                self.finish(task, success: true, kind: kind, reschedule: true)
            case .retryableFailure:
                self.finish(task, success: false, kind: kind, reschedule: true)
            case .cancelled, .needsUserAttention:
                self.finish(task, success: false, kind: kind, reschedule: false)
            }
        }
    }

    private func finish(
        _ task: IOSBackgroundTaskExecution,
        success: Bool,
        kind: BackgroundTaskKind,
        reschedule: Bool
    ) {
        task.setTaskCompleted(success: success)
        guard reschedule else { return }
        switch kind {
        case .appRefresh:
            _ = scheduleAppRefresh()
        case .processing:
            _ = scheduleProcessing()
        }
    }
}

private final class CancellationBox {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func cancel() {
        lock.lock(); value = true; lock.unlock()
    }
}

#if os(iOS) && canImport(BackgroundTasks)
import BackgroundTasks
import UserNotifications

extension BGTask: IOSBackgroundTaskExecution {}

private final class SystemBackgroundTaskSchedulingPort: IOSBackgroundTaskSchedulingPort {
    @discardableResult
    func register(
        forTaskWithIdentifier identifier: String,
        handler: @escaping (IOSBackgroundTaskExecution) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handler(task)
        }
    }

    func submit(_ request: IOSBackgroundTaskRequest) throws {
        switch request.kind {
        case .appRefresh:
            let task = BGAppRefreshTaskRequest(identifier: request.identifier)
            task.earliestBeginDate = request.earliestBeginDate
            try BGTaskScheduler.shared.submit(task)
        case .processing:
            let task = BGProcessingTaskRequest(identifier: request.identifier)
            task.earliestBeginDate = request.earliestBeginDate
            task.requiresNetworkConnectivity = request.requiresNetworkConnectivity
            task.requiresExternalPower = request.requiresExternalPower
            try BGTaskScheduler.shared.submit(task)
        }
    }
}

private struct SystemNotificationAuthorizationPort: IOSNotificationAuthorizationPort {
    func requestAuthorization(completion: ((Bool) -> Void)?) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, _ in
            DispatchQueue.main.async { completion?(granted) }
        }
    }
}

public final class IOSUserAttentionNotifier: SyncUserAttentionNotifier, IOSNotificationAuthorizationPort {
    private let authorization: IOSNotificationAuthorizationPort

    public init(authorization: IOSNotificationAuthorizationPort = SystemNotificationAuthorizationPort()) {
        self.authorization = authorization
    }

    public func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        authorization.requestAuthorization(completion: completion)
    }

    public func notifyUserToOpenApp(reason: AuthenticationAttentionReason) {
        let content = UNMutableNotificationContent()
        content.title = "翱翔助手需要处理"
        content.body = message(for: reason)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "aoxiang-auth-attention",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func message(for reason: AuthenticationAttentionReason) -> String {
        switch reason {
        case .loginRequired: return "请打开 App 完成登录"
        case .collectionNotReady: return "请打开 App 完成采集准备"
        case .invalidCredentials: return "请打开 App 检查登录信息"
        case .invalidSMS, .smsRequired: return "请打开 App 完成短信验证"
        case .authenticationExpired: return "认证已失效，请打开 App 重新登录"
        }
    }
}

public extension IOSBackgroundTaskScheduler {
    /// Production constructor: the caller still injects the authenticated
    /// runner factory, while all system-only ports stay in this iOS adapter.
    convenience init(
        refreshIdentifier: String = "cn.nwpu.aoxiang.refresh",
        processingIdentifier: String = "cn.nwpu.aoxiang.processing",
        coordinator: BackgroundSyncCoordinator,
        runnerFactory: IOSBackgroundRunnerFactory,
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            refreshIdentifier: refreshIdentifier,
            processingIdentifier: processingIdentifier,
            coordinator: coordinator,
            runnerFactory: runnerFactory,
            schedulingPort: SystemBackgroundTaskSchedulingPort(),
            notificationAuthorization: SystemNotificationAuthorizationPort(),
            now: now
        )
    }
}
#endif
