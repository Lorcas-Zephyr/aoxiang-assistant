import Foundation

public enum BackgroundTaskKind: String, Codable, Equatable {
    case appRefresh
    case processing
}

public struct BackgroundSyncRequest: Codable, Equatable {
    public let kind: BackgroundTaskKind
    public let requestedAtEpochMilliseconds: Int64
    public let requiresNetwork: Bool
    public let allowsExpensiveNetwork: Bool

    public init(
        kind: BackgroundTaskKind,
        requestedAtEpochMilliseconds: Int64,
        requiresNetwork: Bool = true,
        allowsExpensiveNetwork: Bool = false
    ) {
        self.kind = kind
        self.requestedAtEpochMilliseconds = requestedAtEpochMilliseconds
        self.requiresNetwork = requiresNetwork
        self.allowsExpensiveNetwork = allowsExpensiveNetwork
    }
}

public enum BackgroundSyncFailure: String, Codable, Equatable {
    case networkUnavailable
    case serverUnavailable
    case rateLimited
    case invalidResponse
    case authenticationExpired
    case smsRequired
    case cancelled
}

public enum BackgroundSyncOutcome: Equatable {
    case success(WidgetSnapshot)
    case needsUserAttention(AuthenticationAttentionReason)
    case retryableFailure(RetryableAuthenticationFailure)
    case cancelled
}

public struct BackgroundSyncStatus: Codable, Equatable {
    public enum State: String, Codable, Equatable {
        case neverRun
        case succeeded
        case retryScheduled
        case needsUserAttention
        case cancelled
    }

    public let state: State
    public let lastAttemptEpochMilliseconds: Int64?
    public let lastSuccessEpochMilliseconds: Int64?
    public let retryCount: Int
    public let attentionReason: AuthenticationAttentionReason?
    public let failureReason: AuthenticationFailureReason?

    public init(
        state: State = .neverRun,
        lastAttemptEpochMilliseconds: Int64? = nil,
        lastSuccessEpochMilliseconds: Int64? = nil,
        retryCount: Int = 0,
        attentionReason: AuthenticationAttentionReason? = nil,
        failureReason: AuthenticationFailureReason? = nil
    ) {
        self.state = state
        self.lastAttemptEpochMilliseconds = lastAttemptEpochMilliseconds
        self.lastSuccessEpochMilliseconds = lastSuccessEpochMilliseconds
        self.retryCount = retryCount
        self.attentionReason = attentionReason
        self.failureReason = failureReason
    }
}

public protocol BackgroundSyncStatusStore {
    func load() throws -> BackgroundSyncStatus
    func save(_ status: BackgroundSyncStatus) throws
}

public final class InMemoryBackgroundSyncStatusStore: BackgroundSyncStatusStore {
    public var value: BackgroundSyncStatus
    public var shouldFailWrites = false

    public init(value: BackgroundSyncStatus = BackgroundSyncStatus()) {
        self.value = value
    }

    public func load() throws -> BackgroundSyncStatus { value }

    public func save(_ status: BackgroundSyncStatus) throws {
        guard !shouldFailWrites else {
            throw OfflineDataError.persistenceFailed("injected sync status write failure")
        }
        value = status
    }
}

public final class FileBackgroundSyncStatusStore: BackgroundSyncStatusStore {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> BackgroundSyncStatus {
        guard fileManager.fileExists(atPath: fileURL.path) else { return BackgroundSyncStatus() }
        do {
            return try JSONDecoder().decode(
                BackgroundSyncStatus.self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            throw OfflineDataError.persistenceFailed(error.localizedDescription)
        }
    }

    public func save(_ status: BackgroundSyncStatus) throws {
        do {
            let parent = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let temporaryURL = parent.appendingPathComponent(".sync-status-\(UUID().uuidString).tmp")
            defer { try? fileManager.removeItem(at: temporaryURL) }
            try JSONEncoder().encode(status).write(to: temporaryURL, options: [.atomic])
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch {
            throw OfflineDataError.persistenceFailed(error.localizedDescription)
        }
    }
}

public protocol BackgroundSyncRunner {
    func run(
        request: BackgroundSyncRequest,
        isCancelled: @escaping () -> Bool
    ) -> BackgroundSyncOutcome
}

public protocol SyncUserAttentionNotifier {
    func notifyUserToOpenApp(reason: AuthenticationAttentionReason)
}

public struct NoopSyncUserAttentionNotifier: SyncUserAttentionNotifier {
    public init() {}
    public func notifyUserToOpenApp(reason: AuthenticationAttentionReason) {}
}

/// Coordinates one best-effort task. It never creates a hidden WebView and
/// commits a widget snapshot only after a successful runner result.
public final class BackgroundSyncCoordinator {
    private let statusStore: BackgroundSyncStatusStore
    private let snapshotStore: ReversibleWidgetSnapshotStore
    private let notifier: SyncUserAttentionNotifier
    private let authentication: () -> AuthenticationState

    public init(
        statusStore: BackgroundSyncStatusStore,
        snapshotWriter: ReversibleWidgetSnapshotStore,
        notifier: SyncUserAttentionNotifier = NoopSyncUserAttentionNotifier(),
        authentication: @escaping () -> AuthenticationState
    ) {
        self.statusStore = statusStore
        self.snapshotStore = snapshotWriter
        self.notifier = notifier
        self.authentication = authentication
    }

    @discardableResult
    public func run(
        request: BackgroundSyncRequest,
        runner: BackgroundSyncRunner,
        isCancelled: @escaping () -> Bool = { false }
    ) throws -> BackgroundSyncOutcome {
        let now = request.requestedAtEpochMilliseconds
        if isCancelled() {
            let status = BackgroundSyncStatus(
                state: .cancelled,
                lastAttemptEpochMilliseconds: now
            )
            try statusStore.save(status)
            return .cancelled
        }

        switch authentication() {
        case .needsLogin:
            let reason: AuthenticationAttentionReason = .loginRequired
            try recordAttention(reason: reason, now: now)
            return .needsUserAttention(reason)
        case .needsUserAttention(reason: .invalidCredentials):
            let reason: AuthenticationAttentionReason = .invalidCredentials
            try recordAttention(reason: reason, now: now)
            return .needsUserAttention(reason)
        case .needsSMS:
            let reason: AuthenticationAttentionReason = .smsRequired
            try recordAttention(reason: reason, now: now)
            return .needsUserAttention(reason)
        case .needsUserAttention(let reason):
            try recordAttention(reason: reason, now: now)
            return .needsUserAttention(reason)
        case .authenticated:
            let reason: AuthenticationAttentionReason = .collectionNotReady
            try recordAttention(reason: reason, now: now)
            return .needsUserAttention(reason)
        case .readyToCollect:
            break
        case .retryableFailure(let failure):
            try recordRetry(failure: failure, now: now)
            return .retryableFailure(failure)
        }

        if isCancelled() {
            let status = BackgroundSyncStatus(
                state: .cancelled,
                lastAttemptEpochMilliseconds: now
            )
            try statusStore.save(status)
            return .cancelled
        }

        let outcome = runner.run(request: request, isCancelled: isCancelled)
        switch outcome {
        case .success(let snapshot):
            guard !isCancelled() else {
                let status = BackgroundSyncStatus(
                    state: .cancelled,
                    lastAttemptEpochMilliseconds: now
                )
                try statusStore.save(status)
                return .cancelled
            }
            // Both files are individually atomic. Keep the previous snapshot
            // until the status commit succeeds, then restore it on failure so
            // a failed run cannot publish a misleading new widget value.
            let validatedSnapshot = try snapshot.validated()
            let previousSnapshot = try snapshotStore.read()
            try snapshotStore.write(validatedSnapshot)
            do {
                try statusStore.save(BackgroundSyncStatus(
                state: .succeeded,
                lastAttemptEpochMilliseconds: now,
                lastSuccessEpochMilliseconds: now
                ))
            } catch {
                do {
                    try snapshotStore.restore(previousSnapshot)
                } catch let rollbackError {
                    throw OfflineDataError.persistenceFailed(
                        "sync status commit failed and snapshot rollback failed: \(rollbackError.localizedDescription)"
                    )
                }
                throw error
            }
        case .needsUserAttention(let reason):
            try recordAttention(reason: reason, now: now)
        case .retryableFailure(let failure):
            try recordRetry(failure: failure, now: now)
        case .cancelled:
            try statusStore.save(BackgroundSyncStatus(
                state: .cancelled,
                lastAttemptEpochMilliseconds: now
            ))
        }
        return outcome
    }

    private func recordAttention(reason: AuthenticationAttentionReason, now: Int64) throws {
        try statusStore.save(BackgroundSyncStatus(
            state: .needsUserAttention,
            lastAttemptEpochMilliseconds: now,
            attentionReason: reason
        ))
        notifier.notifyUserToOpenApp(reason: reason)
    }

    private func recordRetry(
        failure: RetryableAuthenticationFailure,
        now: Int64
    ) throws {
        let previous = try statusStore.load()
        try statusStore.save(BackgroundSyncStatus(
            state: .retryScheduled,
            lastAttemptEpochMilliseconds: now,
            retryCount: previous.retryCount + 1,
            failureReason: failure.reason
        ))
    }
}

public struct StaticBackgroundSyncRunner: BackgroundSyncRunner {
    private let outcome: BackgroundSyncOutcome

    public init(outcome: BackgroundSyncOutcome) {
        self.outcome = outcome
    }

    public func run(
        request: BackgroundSyncRequest,
        isCancelled: @escaping () -> Bool
    ) -> BackgroundSyncOutcome {
        isCancelled() ? .cancelled : outcome
    }
}
