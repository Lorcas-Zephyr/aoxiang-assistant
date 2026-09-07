import Foundation
import XCTest
@testable import AoxiangCore

private final class RecordingNotifier: SyncUserAttentionNotifier {
    var reasons: [AuthenticationAttentionReason] = []
    func notifyUserToOpenApp(reason: AuthenticationAttentionReason) { reasons.append(reason) }
}

private final class RecordingSnapshotWriter: ReversibleWidgetSnapshotStore {
    var snapshots: [WidgetSnapshot] = []
    var shouldFail = false
    func write(_ snapshot: WidgetSnapshot) throws {
        if shouldFail { throw OfflineDataError.persistenceFailed("injected snapshot failure") }
        snapshots.append(snapshot)
    }

    func read() throws -> WidgetSnapshot? { snapshots.last }

    func restore(_ snapshot: WidgetSnapshot?) throws {
        snapshots = snapshot.map { [$0] } ?? []
    }
}

final class BackgroundSyncTests: XCTestCase {
    private func request() -> BackgroundSyncRequest {
        BackgroundSyncRequest(kind: .appRefresh, requestedAtEpochMilliseconds: 1_700_000_000_000)
    }

    private func snapshot() -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAtEpochMilliseconds: 1_700_000_000_000,
            selectedSemesterName: "学期",
            todayCourses: [],
            gradeSummary: WidgetGradeSummary(count: 0, averageScore: nil, gpa: nil)
        )
    }

    func testSuccessfulSyncWritesSnapshotAndMarksLastSuccess() throws {
        let statuses = InMemoryBackgroundSyncStatusStore()
        let writer = RecordingSnapshotWriter()
        let coordinator = BackgroundSyncCoordinator(
            statusStore: statuses,
            snapshotWriter: writer,
            authentication: { .readyToCollect }
        )

        let result = try coordinator.run(
            request: request(),
            runner: StaticBackgroundSyncRunner(outcome: .success(snapshot()))
        )

        XCTAssertEqual(result, .success(snapshot()))
        XCTAssertEqual(writer.snapshots, [snapshot()])
        XCTAssertEqual(statuses.value.state, .succeeded)
        XCTAssertEqual(statuses.value.lastSuccessEpochMilliseconds, request().requestedAtEpochMilliseconds)
    }

    func testAuthenticationExpiryDoesNotRunCollectorAndNotifiesUser() throws {
        let statuses = InMemoryBackgroundSyncStatusStore()
        let writer = RecordingSnapshotWriter()
        let notifier = RecordingNotifier()
        let coordinator = BackgroundSyncCoordinator(
            statusStore: statuses,
            snapshotWriter: writer,
            notifier: notifier,
            authentication: { .needsUserAttention(reason: .authenticationExpired) }
        )

        let result = try coordinator.run(
            request: request(),
            runner: StaticBackgroundSyncRunner(outcome: .success(snapshot()))
        )

        XCTAssertEqual(result, .needsUserAttention(.authenticationExpired))
        XCTAssertTrue(writer.snapshots.isEmpty)
        XCTAssertEqual(notifier.reasons, [.authenticationExpired])
        XCTAssertEqual(statuses.value.state, .needsUserAttention)
    }

    func testMissingLoginIsDistinctFromRejectedCredentials() throws {
        let statuses = InMemoryBackgroundSyncStatusStore()
        let notifier = RecordingNotifier()
        let coordinator = BackgroundSyncCoordinator(
            statusStore: statuses,
            snapshotWriter: RecordingSnapshotWriter(),
            notifier: notifier,
            authentication: { .needsLogin }
        )

        let result = try coordinator.run(
            request: request(),
            runner: StaticBackgroundSyncRunner(outcome: .success(snapshot()))
        )

        XCTAssertEqual(result, .needsUserAttention(.loginRequired))
        XCTAssertEqual(statuses.value.attentionReason, .loginRequired)
        XCTAssertEqual(notifier.reasons, [.loginRequired])
    }

    func testAuthenticatedButNotPreparedStateDoesNotRunBackgroundCollector() throws {
        let statuses = InMemoryBackgroundSyncStatusStore()
        let writer = RecordingSnapshotWriter()
        let coordinator = BackgroundSyncCoordinator(
            statusStore: statuses,
            snapshotWriter: writer,
            authentication: { .authenticated }
        )

        let result = try coordinator.run(
            request: request(),
            runner: StaticBackgroundSyncRunner(outcome: .success(snapshot()))
        )

        XCTAssertEqual(result, .needsUserAttention(.collectionNotReady))
        XCTAssertTrue(writer.snapshots.isEmpty)
    }

    func testSmsStateIsRecordedAsPendingAttention() throws {
        let statuses = InMemoryBackgroundSyncStatusStore()
        let notifier = RecordingNotifier()
        let coordinator = BackgroundSyncCoordinator(
            statusStore: statuses,
            snapshotWriter: RecordingSnapshotWriter(),
            notifier: notifier,
            authentication: { .needsSMS }
        )

        XCTAssertEqual(
            try coordinator.run(request: request(), runner: StaticBackgroundSyncRunner(outcome: .success(snapshot()))),
            .needsUserAttention(.smsRequired)
        )
        XCTAssertEqual(statuses.value.attentionReason, .smsRequired)
        XCTAssertEqual(notifier.reasons, [.smsRequired])
    }

    func testCancelledTaskDoesNotReplaceExistingSnapshot() throws {
        let statuses = InMemoryBackgroundSyncStatusStore()
        let writer = RecordingSnapshotWriter()
        let old = snapshot()
        writer.snapshots = [old]
        let coordinator = BackgroundSyncCoordinator(
            statusStore: statuses,
            snapshotWriter: writer,
            authentication: { .readyToCollect }
        )

        let result = try coordinator.run(
            request: request(),
            runner: StaticBackgroundSyncRunner(outcome: .success(snapshot())),
            isCancelled: { true }
        )

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(writer.snapshots, [old])
        XCTAssertEqual(statuses.value.state, .cancelled)
    }

    func testRetryableFailureIncrementsRetryCountWithoutFakingSuccess() throws {
        let statuses = InMemoryBackgroundSyncStatusStore()
        let writer = RecordingSnapshotWriter()
        let failure = RetryableAuthenticationFailure(operation: .collection, reason: .serverUnavailable)
        let coordinator = BackgroundSyncCoordinator(
            statusStore: statuses,
            snapshotWriter: writer,
            authentication: { .readyToCollect }
        )

        let result = try coordinator.run(
            request: request(),
            runner: StaticBackgroundSyncRunner(outcome: .retryableFailure(failure))
        )

        XCTAssertEqual(result, .retryableFailure(failure))
        XCTAssertEqual(statuses.value.state, .retryScheduled)
        XCTAssertEqual(statuses.value.retryCount, 1)
        XCTAssertTrue(writer.snapshots.isEmpty)
    }

    func testStatusCommitFailureRollsBackTheNewWidgetSnapshot() throws {
        let statuses = InMemoryBackgroundSyncStatusStore()
        let writer = RecordingSnapshotWriter()
        let old = snapshot()
        let newer = WidgetSnapshot(
            generatedAtEpochMilliseconds: old.generatedAtEpochMilliseconds + 1,
            selectedSemesterName: "新学期",
            todayCourses: [],
            gradeSummary: old.gradeSummary
        )
        writer.snapshots = [old]
        statuses.shouldFailWrites = true
        let coordinator = BackgroundSyncCoordinator(
            statusStore: statuses,
            snapshotWriter: writer,
            authentication: { .readyToCollect }
        )

        XCTAssertThrowsError(try coordinator.run(
            request: request(),
            runner: StaticBackgroundSyncRunner(outcome: .success(newer))
        ))
        XCTAssertEqual(writer.snapshots, [old])
        XCTAssertEqual(statuses.value.state, .neverRun)
    }
}
