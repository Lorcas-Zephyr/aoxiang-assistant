import Foundation
import AoxiangCore

#if os(iOS) && canImport(BackgroundTasks) && canImport(SwiftUI)
import BackgroundTasks
import SwiftUI

/// Owns iOS-only task registration and scheduling for the application scene.
/// The default runner is deliberately unconfigured: until a real foreground
/// collector is injected, a background invocation records a user-attention
/// state and cannot fabricate a successful snapshot.
@MainActor
public final class IOSApplicationLifecycle: ObservableObject {
    public let authenticationStore: AuthenticationSessionStore
    private let scheduler: IOSBackgroundTaskScheduler
    private let canWriteWidgetSnapshot: Bool

    public init(
        authenticationStore: AuthenticationSessionStore = AuthenticationSessionStore(),
        fileManager: FileManager = .default,
        runnerFactory: IOSBackgroundRunnerFactory? = nil
    ) {
        self.authenticationStore = authenticationStore
        let selectedFactory = runnerFactory ?? ClosureIOSBackgroundRunnerFactory(
            authentication: { authenticationStore.state },
            runner: { UnconfiguredIOSBackgroundRunner() }
        )
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let statusStore = FileBackgroundSyncStatusStore(
            fileURL: applicationSupport.appendingPathComponent("background-sync-status.json"),
            fileManager: fileManager
        )
        canWriteWidgetSnapshot = AoxiangSharedContainer.sharedSnapshotURL(fileManager: fileManager) != nil
        let snapshotWriter = AoxiangSharedContainer.widgetSnapshotStore(fileManager: fileManager)
        let coordinator = BackgroundSyncCoordinator(
            statusStore: statusStore,
            snapshotWriter: snapshotWriter,
            notifier: IOSUserAttentionNotifier(),
            authentication: { selectedFactory.currentAuthentication() }
        )
        scheduler = IOSBackgroundTaskScheduler(
            coordinator: coordinator,
            runnerFactory: selectedFactory
        )
        if canWriteWidgetSnapshot {
            _ = scheduler.register()
            _ = scheduler.requestNotificationAuthorization()
        }
    }

    public func scenePhaseChanged(_ phase: ScenePhase) {
        // A background run cannot publish an atomic shared snapshot without
        // the App Group, so do not collect or schedule a misleading run.
        guard canWriteWidgetSnapshot else { return }
        switch phase {
        case .active:
            _ = scheduler.register()
            _ = scheduler.scheduleAppRefresh()
        case .background:
            _ = scheduler.scheduleAppRefresh()
            _ = scheduler.scheduleProcessing()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
#endif
