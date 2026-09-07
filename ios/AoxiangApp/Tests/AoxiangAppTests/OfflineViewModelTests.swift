import Foundation
import XCTest
import AoxiangCore
@testable import AoxiangApp

#if canImport(SwiftUI)
@MainActor
final class OfflineViewModelTests: XCTestCase {
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
}
#endif
