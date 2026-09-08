import Foundation
import XCTest
import AoxiangCore
@testable import AoxiangApp

#if canImport(SwiftUI)
@MainActor
final class OfflineViewModelTests: XCTestCase {
    private final class RecordingTimelineReloader: WidgetTimelineReloader {
        private(set) var reloadCount = 0

        func reloadAllTimelines() {
            reloadCount += 1
        }
    }

    func testImportAndLocalEditPublishState() throws {
        let store = InMemoryOfflineStateStore()
        let controller = try OfflineDataController(store: store)
        let writer = FileWidgetSnapshotStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("vm-\(UUID().uuidString).json")
        )
        let model = OfflineAppViewModel(controller: controller, snapshotWriter: writer)
        let backup = try AndroidBackupExporter().exportData(from: OfflineAppState(
            semesters: [OfflineSemester(id: "term-1", startDate: "2026-01-01", endDate: "2026-06-30")],
            selectedSemesterId: "term-1"
        ))

        model.importBackup(data: backup)
        XCTAssertTrue(model.lastImportSucceeded)
        model.addCourse(name: "本地课程", semesterId: "term-1")
        XCTAssertEqual(model.state.courses.count, 1)
    }

    func testSuccessfulSnapshotWriteRequestsWidgetTimelineRefresh() throws {
        let store = InMemoryOfflineStateStore()
        let controller = try OfflineDataController(store: store)
        let writer = FileWidgetSnapshotStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("vm-(UUID().uuidString).json")
        )
        let reloader = RecordingTimelineReloader()
        let model = OfflineAppViewModel(
            controller: controller,
            snapshotWriter: writer,
            widgetTimelineReloader: reloader
        )

        model.writeWidgetSnapshot()

        XCTAssertEqual(reloader.reloadCount, 1)
    }

    func testPortalCollectionIsAppliedAtomicallyAndRefreshesWidget() throws {
        let oldState = OfflineAppState(
            semesters: [OfflineSemester(id: "old", startDate: "2026-01-01", endDate: "2026-06-30")],
            selectedSemesterId: "old",
            grades: [OfflineGrade(id: "old-grade", course: "旧课", credits: 1, point: 2.0, score: 60)],
            gpa: 2.0,
            electricityBalance: 5
        )
        let store = InMemoryOfflineStateStore(value: oldState)
        let controller = try OfflineDataController(store: store)
        let snapshotURL = FileManager.default.temporaryDirectory.appendingPathComponent("portal-(UUID().uuidString).json")
        let writer = FileWidgetSnapshotStore(fileURL: snapshotURL)
        let reloader = RecordingTimelineReloader()
        let model = OfflineAppViewModel(controller: controller, snapshotWriter: writer, widgetTimelineReloader: reloader)
        let semester = OfflineSemester(id: "new", startDate: "2026-02-01", endDate: "2026-07-01")
        let course = OfflineCourse(id: "new-course", name: "新课", semesterId: "new")
        let result = PortalCollectedData(
            grades: [OfflineGrade(id: "new-grade", course: "新课", credits: 3, point: 3.7, score: 92)],
            gpa: 3.7,
            schedule: PortalCollectionParsers.SchedulePayload(semesters: [semester], courses: [course]),
            electricityBalance: 18
        )

        XCTAssertTrue(model.applyPortalCollection(result))
        XCTAssertEqual(model.state.selectedSemesterId, "new")
        XCTAssertEqual(model.state.grades.map(\.id), ["new-grade"])
        XCTAssertEqual(model.state.gpa, 3.7)
        XCTAssertEqual(model.state.electricityBalance, 18)
        XCTAssertEqual(try writer.read()?.gradeSummary.gpa, 3.7)
        XCTAssertEqual(reloader.reloadCount, 1)
    }

    func testFailedPortalCollectionPreservesStateAndExistingWidgetSnapshot() throws {
        let oldState = OfflineAppState(
            semesters: [OfflineSemester(id: "old", startDate: "2026-01-01", endDate: "2026-06-30")],
            selectedSemesterId: "old",
            grades: [OfflineGrade(id: "old-grade", course: "旧课", credits: 1, point: 2.0, score: 60)],
            gpa: 2.0,
            electricityBalance: 5
        )
        let store = InMemoryOfflineStateStore(value: oldState)
        let controller = try OfflineDataController(store: store)
        let snapshotURL = FileManager.default.temporaryDirectory.appendingPathComponent("portal-fail-(UUID().uuidString).json")
        let writer = FileWidgetSnapshotStore(fileURL: snapshotURL)
        let model = OfflineAppViewModel(controller: controller, snapshotWriter: writer)
        model.writeWidgetSnapshot()
        let previousSnapshot = try writer.read()
        let invalidResult = PortalCollectedData(
            grades: [],
            schedule: PortalCollectionParsers.SchedulePayload(
                semesters: [OfflineSemester(id: "new", startDate: "2026-02-01", endDate: "2026-07-01")],
                courses: [OfflineCourse(id: "bad", name: "坏引用", semesterId: "missing")]
            ),
            electricityBalance: 18
        )

        XCTAssertFalse(model.applyPortalCollection(invalidResult))
        XCTAssertEqual(model.state, oldState)
        XCTAssertEqual(try writer.read(), previousSnapshot)
    }

    func testPortalCollectionFailsClosedWhenSharedWidgetContainerIsUnavailable() throws {
        let oldState = OfflineAppState(
            semesters: [OfflineSemester(id: "old", startDate: "2026-01-01", endDate: "2026-06-30")],
            selectedSemesterId: "old",
            grades: [OfflineGrade(id: "old-grade", course: "旧课", credits: 1, point: 2.0, score: 60)]
        )
        let store = InMemoryOfflineStateStore(value: oldState)
        let controller = try OfflineDataController(store: store)
        let model = OfflineAppViewModel(
            controller: controller,
            snapshotWriter: UnavailableWidgetSnapshotStore()
        )
        let result = PortalCollectedData(
            grades: [OfflineGrade(id: "new-grade", course: "新课", credits: 3, point: 3.7, score: 92)],
            gpa: 3.7,
            schedule: PortalCollectionParsers.SchedulePayload(
                semesters: [OfflineSemester(id: "new", startDate: "2026-02-01", endDate: "2026-07-01")],
                courses: [OfflineCourse(id: "new-course", name: "新课", semesterId: "new")]
            ),
            electricityBalance: 18
        )

        XCTAssertFalse(model.applyPortalCollection(result))
        XCTAssertEqual(model.state, oldState)
        XCTAssertEqual(store.value, oldState)
    }
}
#endif
