import XCTest
import AoxiangCore
@testable import AoxiangApp

private final class LifecycleRecordingTask: IOSBackgroundTaskExecution {
    var expirationHandler: (() -> Void)?
    private(set) var completedResults: [Bool] = []

    func setTaskCompleted(success: Bool) {
        completedResults.append(success)
    }
}

private final class LifecycleSchedulingPort: IOSBackgroundTaskSchedulingPort {
    struct Registration {
        let identifier: String
        let handler: (IOSBackgroundTaskExecution) -> Void
    }

    var registrationResults: [String: Bool] = [:]
    private(set) var registrations: [Registration] = []
    private(set) var submittedRequests: [IOSBackgroundTaskRequest] = []

    @discardableResult
    func register(
        forTaskWithIdentifier identifier: String,
        handler: @escaping (IOSBackgroundTaskExecution) -> Void
    ) -> Bool {
        registrations.append(Registration(identifier: identifier, handler: handler))
        return registrationResults[identifier] ?? true
    }

    func submit(_ request: IOSBackgroundTaskRequest) throws {
        submittedRequests.append(request)
    }

    func handler(for identifier: String) -> ((IOSBackgroundTaskExecution) -> Void)? {
        registrations.last(where: { $0.identifier == identifier })?.handler
    }
}

private final class LifecycleAuthorizationPort: IOSNotificationAuthorizationPort {
    private(set) var requestCount = 0

    func requestAuthorization(completion: ((Bool) -> Void)?) {
        requestCount += 1
        completion?(true)
    }
}

private final class LifecycleSnapshotWriter: ReversibleWidgetSnapshotStore {
    func read() throws -> WidgetSnapshot? { nil }
    func write(_ snapshot: WidgetSnapshot) throws {}
    func restore(_ snapshot: WidgetSnapshot?) throws {}
}

private struct LifecycleRunner: BackgroundSyncRunner {
    let result: BackgroundSyncOutcome
    let onRun: () -> Void

    func run(
        request: BackgroundSyncRequest,
        isCancelled: @escaping () -> Bool
    ) -> BackgroundSyncOutcome {
        onRun()
        return isCancelled() ? .cancelled : result
    }
}

private struct LifecycleRunnerFactory: IOSBackgroundRunnerFactory {
    let state: AuthenticationState
    let runner: BackgroundSyncRunner

    func makeRunner() -> BackgroundSyncRunner { runner }
    func currentAuthentication() -> AuthenticationState { state }
}

final class BackgroundTaskSchedulerTests: XCTestCase {
    private let refreshID = "test.refresh"
    private let processingID = "test.processing"

    func testRegisterIsIdempotentAndReportsBothHandlers() {
        let port = LifecycleSchedulingPort()
        let scheduler = makeScheduler(port: port)

        XCTAssertTrue(scheduler.register().allRegistered)
        XCTAssertTrue(scheduler.register().allRegistered)
        XCTAssertEqual(port.registrations.map(\.identifier), [refreshID, processingID])
    }

    func testFailedRegistrationOnlyRetriesTheMissingHandler() {
        let port = LifecycleSchedulingPort()
        port.registrationResults[processingID] = false
        let scheduler = makeScheduler(port: port)

        XCTAssertFalse(scheduler.register().allRegistered)
        port.registrationResults[processingID] = true
        XCTAssertTrue(scheduler.register().allRegistered)
        XCTAssertEqual(
            port.registrations.map(\.identifier),
            [refreshID, processingID, processingID]
        )
    }

    func testSchedulingClampsNegativeDelayAndPreservesTaskRequirements() {
        let port = LifecycleSchedulingPort()
        let scheduler = makeScheduler(port: port, now: { Date(timeIntervalSince1970: 100) })

        XCTAssertEqual(scheduler.scheduleAppRefresh(after: -1), .notRegistered)
        XCTAssertTrue(scheduler.register().allRegistered)
        XCTAssertEqual(scheduler.scheduleAppRefresh(after: -1), .submitted)
        XCTAssertEqual(scheduler.scheduleProcessing(after: 5), .submitted)
        XCTAssertEqual(port.submittedRequests.count, 2)
        XCTAssertEqual(port.submittedRequests[0].earliestBeginDate, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(port.submittedRequests[0].kind, .appRefresh)
        XCTAssertTrue(port.submittedRequests[1].requiresNetworkConnectivity)
        XCTAssertFalse(port.submittedRequests[1].requiresExternalPower)
    }

    func testTaskUsesInjectedRunnerAndCompletesWithOutcome() {
        let port = LifecycleSchedulingPort()
        let ran = expectation(description: "runner invoked")
        let runner = LifecycleRunner(
            result: .cancelled,
            onRun: { ran.fulfill() }
        )
        let scheduler = makeScheduler(
            port: port,
            factory: LifecycleRunnerFactory(state: .readyToCollect, runner: runner)
        )
        XCTAssertTrue(scheduler.register().allRegistered)

        let task = LifecycleRecordingTask()
        port.handler(for: refreshID)?(task)
        wait(for: [ran], timeout: 1)
        XCTAssertEqual(task.completedResults, [false])
    }

    func testSuccessfulTaskSchedulesTheNextBestEffortRun() {
        let port = LifecycleSchedulingPort()
        let runner = LifecycleRunner(
            result: .success(WidgetSnapshot(
                generatedAtEpochMilliseconds: 1,
                selectedSemesterName: nil,
                todayCourses: [],
                gradeSummary: WidgetGradeSummary(count: 0, averageScore: nil, gpa: nil)
            )),
            onRun: {}
        )
        let scheduler = makeScheduler(
            port: port,
            factory: LifecycleRunnerFactory(state: .readyToCollect, runner: runner)
        )
        XCTAssertTrue(scheduler.register().allRegistered)
        let task = LifecycleRecordingTask()

        port.handler(for: refreshID)?(task)
        let deadline = Date().addingTimeInterval(1)
        while task.completedResults.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(task.completedResults, [true])
        XCTAssertEqual(port.submittedRequests.map(\.identifier), [refreshID])
    }

    func testUserAttentionDoesNotCreateAnEndlessBackgroundRetryLoop() {
        let port = LifecycleSchedulingPort()
        let runner = LifecycleRunner(
            result: .needsUserAttention(.loginRequired),
            onRun: {}
        )
        let scheduler = makeScheduler(
            port: port,
            factory: LifecycleRunnerFactory(state: .readyToCollect, runner: runner)
        )
        XCTAssertTrue(scheduler.register().allRegistered)
        let task = LifecycleRecordingTask()

        port.handler(for: refreshID)?(task)
        let deadline = Date().addingTimeInterval(1)
        while task.completedResults.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(task.completedResults, [false])
        XCTAssertEqual(port.submittedRequests, [])
    }

    func testNotificationAuthorizationIsRequestedThroughInjectedPort() {
        let port = LifecycleSchedulingPort()
        let authorization = LifecycleAuthorizationPort()
        let scheduler = makeScheduler(port: port, authorization: authorization)

        XCTAssertTrue(scheduler.requestNotificationAuthorization())
        XCTAssertEqual(authorization.requestCount, 1)
    }

    private func makeScheduler(
        port: LifecycleSchedulingPort,
        factory: IOSBackgroundRunnerFactory? = nil,
        authorization: IOSNotificationAuthorizationPort? = nil,
        now: @escaping () -> Date = Date.init
    ) -> IOSBackgroundTaskScheduler {
        let selectedFactory = factory ?? LifecycleRunnerFactory(
            state: .needsLogin,
            runner: StaticBackgroundSyncRunner(outcome: .cancelled)
        )
        let coordinator = BackgroundSyncCoordinator(
            statusStore: InMemoryBackgroundSyncStatusStore(),
            snapshotWriter: LifecycleSnapshotWriter(),
            authentication: { selectedFactory.currentAuthentication() }
        )
        return IOSBackgroundTaskScheduler(
            refreshIdentifier: refreshID,
            processingIdentifier: processingID,
            coordinator: coordinator,
            runnerFactory: selectedFactory,
            schedulingPort: port,
            notificationAuthorization: authorization,
            now: now
        )
    }
}
