import XCTest
@testable import AoxiangCore

final class PortalEndpointTests: XCTestCase {
    func testEducationRequestsAreAllowListedAndNoStore() throws {
        let request = try PortalEndpoints.gradeInfo(studentID: "student-1", semesterID: "term-1")
        XCTAssertEqual(request.url.host, PortalEndpoints.educationHost)
        XCTAssertEqual(request.url.path, "/student/for-std/grade/sheet/info/student-1")
        XCTAssertEqual(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.query, "semester=term-1")
        XCTAssertEqual(request.headers["Accept"], "application/json")
        XCTAssertEqual(request.headers["Cache-Control"], "no-store")
        XCTAssertEqual(request.timeoutInterval, 12)
    }

    func testPageRequestsMatchAndroidWebViewNegotiation() {
        let gradeSheet = PortalEndpoints.gradeSheet()
        // Foundation on Windows normalizes URL.path by dropping a terminal
        // slash; absoluteString is the request representation sent to WebKit.
        XCTAssertTrue(gradeSheet.url.absoluteString.hasSuffix("/student/for-std/grade/sheet/"))
        XCTAssertTrue(gradeSheet.headers["Accept"]?.contains("text/html") == true)
        XCTAssertEqual(gradeSheet.headers["Cache-Control"], "no-store")

        let courseTable = PortalEndpoints.courseTable()
        XCTAssertEqual(courseTable.url.path, "/student/for-std/course-table")
        XCTAssertTrue(courseTable.headers["Accept"]?.contains("text/html") == true)
    }

    func testEndpointIdentifiersRejectPathTraversalAndEmptyValues() {
        XCTAssertThrowsError(try PortalEndpoints.gpa(studentID: "../cookies")) { error in
            XCTAssertEqual(error as? PortalEndpointError, .invalidIdentifier)
        }
        XCTAssertThrowsError(try PortalEndpoints.printData(studentID: "", semesterID: "term")) { error in
            XCTAssertEqual(error as? PortalEndpointError, .invalidIdentifier)
        }
    }

    func testElectricityIsExplicitlyAVisiblePageCapability() {
        let url = PortalEndpoints.electricityPage()
        XCTAssertEqual(url.host, PortalEndpoints.electricityHost)
        XCTAssertEqual(url.path, "/jfdt/charge/feeitem/toAppitem")
    }
}
