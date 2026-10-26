import XCTest
@testable import AoxiangCore

final class PortalCollectionResultTests: XCTestCase {
    func testIncompleteGradesPreserveGradesButPersistAvailableGPA() throws {
        let previous = OfflineAppState(
            grades: [OfflineGrade(id: "old-grade", course: "旧课", credits: 3, score: 82)]
        )
        let store = InMemoryOfflineStateStore(value: previous)
        let controller = try OfflineDataController(store: store)
        let result = PortalCollectedData(
            grades: [],
            gpa: 3.72,
            schedule: PortalCollectionParsers.SchedulePayload(semesters: [], courses: []),
            warnings: [.gradesUnavailable],
            gradesAvailable: false
        )

        try controller.replace(result.applying(to: controller.state))

        XCTAssertEqual(controller.state.grades.map(\.id), ["old-grade"])
        XCTAssertEqual(controller.state.gpa, 3.72)
        XCTAssertEqual(store.value?.gpa, 3.72)
    }

}
