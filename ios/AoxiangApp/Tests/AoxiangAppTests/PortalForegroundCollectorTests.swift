import Foundation
import XCTest
import AoxiangCore
@testable import AoxiangApp

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PortalForegroundCollectorTests: XCTestCase {
    private final class RecordingTransport: PortalCollectionTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var recordedRequests: [StableHTTPCollectionRequest] = []
        private var responses: [String: [Result<Data, Error>]]

        init(responses: [String: [Result<Data, Error>]]) {
            self.responses = responses
        }

        var requests: [StableHTTPCollectionRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recordedRequests
        }

        func send(_ request: StableHTTPCollectionRequest) async throws -> (Data, HTTPURLResponse) {
            let result = dequeue(request)
            guard let result else { throw CollectionTransportError.nonSuccessStatus(404) }
            let data = try result.get()
            return (
                data,
                HTTPURLResponse(
                    url: request.url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
            )
        }

        private func dequeue(_ request: StableHTTPCollectionRequest) -> Result<Data, Error>? {
            lock.lock()
            defer { lock.unlock() }
            recordedRequests.append(request)
            let path = request.url.path
            guard var queue = responses[path], !queue.isEmpty else { return nil }
            let result = queue.removeFirst()
            responses[path] = queue
            return result
        }
    }

    private struct TestTransportError: Error {}

    func testCollectionRejectsStatesThatAreNotReady() async {
        let transport = RecordingTransport(responses: [:])
        let collector = PortalForegroundCollector(transport: transport) { 10 }

        do {
            _ = try await collector.collect(state: .authenticated)
            XCTFail("expected collectionNotReady failure")
        } catch let error as PortalCollectionFailure {
            XCTAssertEqual(error, .invalidResponse("collection not prepared"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testCollectionUsesAllowListedRequestsAndMergesValidData() async throws {
        let transport = makeTransport(gpa: .success(json(["gpa": 3.72])))
        let electricityCalls = LockedCounter()
        let collector = PortalForegroundCollector(transport: transport) {
            electricityCalls.increment()
            return 42.5
        }

        let result = try await collector.collect(state: .readyToCollect)

        XCTAssertEqual(result.electricityBalance ?? -1, 42.5, accuracy: 0.0001)
        XCTAssertEqual(result.grades.count, 1)
        XCTAssertEqual(result.grades.first?.course, "数学")
        XCTAssertEqual(result.grades.first?.score, 95)
        XCTAssertEqual(result.schedule.semesters.map(\.id), ["term-1"])
        XCTAssertEqual(result.schedule.courses.count, 1)
        XCTAssertEqual(result.schedule.courses.first?.teacher, "张老师")
        XCTAssertEqual(result.schedule.courses.first?.location, "长安 A 101")
        XCTAssertEqual(electricityCalls.value, 1)

        XCTAssertEqual(
            transport.requests.map { $0.url.path },
            [
                "/student/for-std/grade/sheet",
                "/student/for-std/grade/sheet/info/student-1",
                "/student/for-std/grade/sheet/info/student-1",
                "/student/for-std/student-portrait/getMyGpa",
                "/student/for-std/course-table",
                "/student/ws/semester/get/term-1",
                "/student/for-std/course-table/semester/term-1/print-data/student-1",
            ]
        )
        XCTAssertEqual(transport.requests[1].url.query, "semester=term-1")
        XCTAssertEqual(transport.requests[3].url.query, "studentAssoc=student-1")
        XCTAssertTrue(transport.requests.allSatisfy { $0.headers["Cache-Control"] == "no-store" })
    }

    func testCollectionContinuesWhenGPAResponseIsMalformedAndUsesPortraitFallbackPath() async throws {
        let transport = makeTransport(gpa: .success(Data("malformed".utf8)))
        let collector = PortalForegroundCollector(transport: transport) { 0 }

        let result = try await collector.collect(
            state: .readyToCollect,
            portraitHTML: "<span>累计平均学分绩点：3.41</span>"
        )

        XCTAssertEqual(result.grades.count, 1)
        XCTAssertEqual(result.schedule.courses.count, 1)
    }

    func testCollectionUsesVisiblePortraitProviderWhenGPAEndpointIsMissing() async throws {
        let transport = makeTransport(gpa: .success(Data("{}".utf8)))
        let portraitCalls = LockedCounter()
        let collector = PortalForegroundCollector(
            transport: transport,
            electricityProvider: { 0 },
            portraitProvider: {
                portraitCalls.increment()
                return "<span>累计平均学分绩点：3.41</span>"
            }
        )

        let result = try await collector.collect(state: .readyToCollect)

        XCTAssertEqual(portraitCalls.value, 1)
        XCTAssertEqual(result.gpa ?? -1, 3.41, accuracy: 0.0001)
    }

    func testVisibleEducationRetryableFailureFallsBackToStableHTTPCollection() async throws {
        let transport = makeTransport(gpa: .success(json(["gpa": 3.72])))
        let visibleCalls = LockedCounter()
        let collector = PortalForegroundCollector(
            transport: transport,
            electricityProvider: { 18 },
            visibleEducationProvider: {
                visibleCalls.increment()
                throw PortalCollectionFailure.retryable(.serverUnavailable)
            }
        )

        let result = try await collector.collect(state: .readyToCollect)

        XCTAssertEqual(visibleCalls.value, 1)
        XCTAssertEqual(result.grades.first?.course, "数学")
        XCTAssertEqual(result.electricityBalance ?? -1, 18, accuracy: 0.0001)
        XCTAssertFalse(transport.requests.isEmpty)
    }

    func testVisibleEducationProviderRunsInsideAuthenticatedPathBeforeStableHTTP() async throws {
        let transport = RecordingTransport(responses: [:])
        let education = PortalVisibleEducationData(
            grades: [OfflineGrade(id: "grade-1", course: "数学", credits: 3, point: 4, score: 95)],
            gpa: 3.8,
            schedule: PortalCollectionParsers.SchedulePayload(
                semesters: [OfflineSemester(id: "term-1", startDate: "2026-01-01", endDate: "2026-07-01")],
                courses: [OfflineCourse(id: "course-1", name: "数学", semesterId: "term-1")]
            )
        )
        let educationCalls = LockedCounter()
        let collector = PortalForegroundCollector(
            transport: transport,
            electricityProvider: { 18 },
            visibleEducationProvider: {
                educationCalls.increment()
                return education
            }
        )

        let result = try await collector.collect(state: .readyToCollect)

        XCTAssertEqual(educationCalls.value, 1)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertEqual(result.grades.first?.course, "数学")
        XCTAssertEqual(result.electricityBalance ?? -1, 18)
    }

    func testVisibleEducationProviderUsesPortraitFallbackWhenItsGPAIsMissing() async throws {
        let transport = RecordingTransport(responses: [:])
        let portraitCalls = LockedCounter()
        let education = PortalVisibleEducationData(
            grades: [OfflineGrade(id: "grade-1", course: "数学", credits: 3, point: 4, score: 95)],
            gpa: nil,
            schedule: PortalCollectionParsers.SchedulePayload(
                semesters: [OfflineSemester(id: "term-1", startDate: "2026-01-01", endDate: "2026-07-01")],
                courses: []
            )
        )
        let collector = PortalForegroundCollector(
            transport: transport,
            electricityProvider: { 18 },
            portraitProvider: {
                portraitCalls.increment()
                return "<span>累计平均学分绩点：3.41</span>"
            },
            visibleEducationProvider: { education }
        )

        let result = try await collector.collect(state: .readyToCollect)

        XCTAssertEqual(portraitCalls.value, 1)
        XCTAssertEqual(result.gpa ?? -1, 3.41, accuracy: 0.0001)
    }

    func testVisibleEducationIsCommittedWhenElectricityPageIsUnavailable() async throws {
        let transport = RecordingTransport(responses: [:])
        let education = PortalVisibleEducationData(
            grades: [OfflineGrade(id: "grade-1", course: "数学", credits: 3, point: 4, score: 95)],
            gpa: 3.8,
            schedule: PortalCollectionParsers.SchedulePayload(
                semesters: [OfflineSemester(id: "term-1", startDate: "2026-01-01", endDate: "2026-07-01")],
                courses: []
            )
        )
        let collector = PortalForegroundCollector(
            transport: transport,
            electricityProvider: {
                throw PortalCollectionFailure.retryable(.serverUnavailable)
            },
            visibleEducationProvider: { education }
        )

        let result = try await collector.collect(state: .readyToCollect)

        XCTAssertEqual(result.grades.map(\.course), ["数学"])
        XCTAssertNil(result.electricityBalance)
        XCTAssertEqual(result.scheduleAvailable, true)
        XCTAssertEqual(result.warnings, [.electricityUnavailable])
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testStableGradesAreCommittedWhenScheduleEndpointIsUnavailable() async throws {
        let gradeSheet = json(["studentId": "student-1", "semesterIds": ["term-1"]])
        let gradeResponse = json([
            "semesterId2studentGrades": ["term-1": [[
                "published": true,
                "course": ["nameZh": "数据结构", "credits": 3],
                "gp": 4.0,
                "gaGrade": 96,
            ]]],
        ])
        let transport = RecordingTransport(responses: [
            "/student/for-std/grade/sheet": [.success(gradeSheet)],
            "/student/for-std/grade/sheet/info/student-1": [.success(gradeResponse)],
            "/student/for-std/student-portrait/getMyGpa": [.success(json(["gpa": 4.0]))],
            "/student/for-std/course-table": [.failure(TestTransportError())],
        ])
        let collector = PortalForegroundCollector(transport: transport) { 2.5 }

        let result = try await collector.collect(state: .readyToCollect)

        XCTAssertEqual(result.grades.map(\.course), ["数据结构"])
        XCTAssertEqual(result.electricityBalance ?? -1, 2.5, accuracy: 0.0001)
        XCTAssertFalse(result.scheduleAvailable)
        XCTAssertEqual(result.warnings, [.scheduleUnavailable])
    }

    func testVisibleEducationDataIsKeptWhenElectricityIsUnavailable() async throws {
        let education = PortalVisibleEducationData(
            grades: [OfflineGrade(id: "grade-1", course: "成绩保留", credits: 3, point: 4, score: 95)],
            gpa: 3.8,
            schedule: PortalCollectionParsers.SchedulePayload(
                semesters: [OfflineSemester(id: "term-1", startDate: "2026-01-01", endDate: "2026-07-01")],
                courses: [OfflineCourse(id: "course-1", name: "课表保留", semesterId: "term-1")]
            )
        )
        let transport = RecordingTransport(responses: [:])
        let collector = PortalForegroundCollector(
            transport: transport,
            electricityProvider: {
                throw PortalCollectionFailure.retryable(.serverUnavailable)
            },
            visibleEducationProvider: { education }
        )

        let result = try await collector.collect(state: .readyToCollect)

        XCTAssertEqual(result.grades.map(\.course), ["成绩保留"])
        XCTAssertEqual(result.schedule.courses.map(\.name), ["课表保留"])
        XCTAssertNil(result.electricityBalance)
        XCTAssertEqual(result.warnings, [.electricityUnavailable])
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testLoginHTMLIsReportedAsAuthenticationRecovery() async {
        let transport = RecordingTransport(responses: [
            PortalEndpoints.gradeSheet().url.path: [.success(Data("<html>统一身份认证 CAS 登录信息已失效</html>".utf8))]
        ])
        let collector = PortalForegroundCollector(transport: transport) { 12 }

        do {
            _ = try await collector.collect(state: .readyToCollect)
            XCTFail("expected authentication recovery")
        } catch let error as PortalCollectionFailure {
            XCTAssertEqual(error, .authenticationRequired)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCollectionAdvancesToNextSemesterWhenInitialScheduleHasEnded() async throws {
        let transport = makeTransport(
            gpa: .success(json(["gpa": 3.72])),
            includeNextScheduleSemester: true
        )
        let collector = PortalForegroundCollector(transport: transport) { 0 }

        let result = try await collector.collect(state: .readyToCollect, today: "2026-09-08")

        XCTAssertEqual(result.schedule.semesters.map(\.id), ["term-2"])
        XCTAssertEqual(
            transport.requests.map { $0.url.path }.suffix(5),
            [
                "/student/for-std/course-table",
                "/student/ws/semester/get/term-1",
                "/student/for-std/course-table/semester/term-1/print-data/student-1",
                "/student/ws/semester/get/term-2",
                "/student/for-std/course-table/semester/term-2/print-data/student-1",
            ]
        )
    }

    func testCollectionMapsAuthenticationFailureAndDoesNotCallElectricity() async {
        let transport = RecordingTransport(responses: [
            PortalEndpoints.gradeSheet().url.path: [.failure(CollectionTransportError.authenticationRequired)]
        ])
        let electricityCalls = LockedCounter()
        let collector = PortalForegroundCollector(transport: transport) {
            electricityCalls.increment()
            return 12
        }

        do {
            _ = try await collector.collect(state: .readyToCollect)
            XCTFail("expected authentication failure")
        } catch let error as PortalCollectionFailure {
            XCTAssertEqual(error, .authenticationRequired)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(electricityCalls.value, 0)
    }

    func testCollectionMapsAnUnthrownHTTP401ToAuthenticationRecovery() async {
        let transport = StatusRecordingTransport(
            data: Data("<html>登录信息已失效</html>".utf8),
            statusCode: 401
        )
        let collector = PortalForegroundCollector(transport: transport) { 12 }

        do {
            _ = try await collector.collect(state: .readyToCollect)
            XCTFail("expected authentication failure")
        } catch let error as PortalCollectionFailure {
            XCTAssertEqual(error, .authenticationRequired)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testCollectionKeepsEducationWhenElectricityValueIsInvalid() async throws {
        let transport = makeTransport(gpa: .success(json(["gpa": 3.72])))
        let collector = PortalForegroundCollector(transport: transport) { -1 }

        let result = try await collector.collect(state: .readyToCollect)

        XCTAssertEqual(result.grades.count, 1)
        XCTAssertNil(result.electricityBalance)
        XCTAssertEqual(result.warnings, [.electricityUnavailable])
    }

    func testCollectionHonorsCancellationBeforeSendingRequests() async {
        let transport = RecordingTransport(responses: [:])
        let collector = PortalForegroundCollector(transport: transport) { 10 }

        do {
            _ = try await collector.collect(state: .readyToCollect, isCancelled: { true })
            XCTFail("expected cancellation")
        } catch let error as PortalCollectionFailure {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    private func makeTransport(
        gpa: Result<Data, Error>,
        includeNextScheduleSemester: Bool = false
    ) -> RecordingTransport {
        let gradeSheet = json([
            "studentId": "student-1",
            "semesterIds": ["term-1", "term-2"],
        ])
        let gradeOne = json([
            "semesterId2studentGrades": [
                "term-1": [[
                    "published": true,
                    "course": ["nameZh": "数学", "credits": 3],
                    "gp": 3.5,
                    "gaGrade": 88,
                ]],
            ],
        ])
        let gradeTwo = json([
            "semesterId2studentGrades": [
                "term-2": [[
                    "published": true,
                    "course": ["nameZh": "数学", "credits": 3],
                    "gp": 4.0,
                    "gaGrade": 95,
                ]],
            ],
        ])
        let courseTable = includeNextScheduleSemester
            ? json([
                "semesters": [
                    [
                        "id": "term-1",
                        "nameZh": "2026 春",
                        "startDate": "2026-02-23",
                        // Keep the first candidate containing the test date;
                        // the activity-derived end then forces next-semester fallback.
                        "endDate": "2027-01-10",
                    ],
                    [
                        "id": "term-2",
                        "nameZh": "2026 秋",
                        "startDate": "2026-08-31",
                        "endDate": "2027-01-10",
                    ],
                ],
            ])
            : json([
                "semester": [
                    "id": "term-1",
                    "nameZh": "2026 春",
                    "startDate": "2026-02-23",
                    "endDate": "2026-06-30",
                ],
            ])
        let semester = json([
            "id": "term-1",
            "nameZh": "2026 春",
            "startDate": "2026-02-23",
            "endDate": "2026-06-30",
        ])
        let nextSemester = json([
            "id": "term-2",
            "nameZh": "2026 秋",
            "startDate": "2026-08-31",
            "endDate": "2027-01-10",
        ])
        let printData = json([
            "studentTableVm": [
                "activities": [[
                    "courseName": "数学",
                    "courseCode": "MATH-101",
                    "weekday": 1,
                    "startUnit": 1,
                    "endUnit": 2,
                    "weekIndexes": [1, 2, 3],
                    "teachers": ["张老师"],
                    "campus": "长安",
                    "building": "A",
                    "room": "101",
                    "credits": 3,
                ]],
            ],
        ])
        let nextPrintData = json([
            "studentTableVm": [
                "activities": [[
                    "courseName": "数学",
                    "courseCode": "MATH-101",
                    "weekday": 1,
                    "startUnit": 1,
                    "endUnit": 2,
                    "weekIndexes": [1, 2, 3],
                    "teachers": ["张老师"],
                    "campus": "长安",
                    "building": "A",
                    "room": "101",
                    "credits": 3,
                ]],
            ],
        ])
        let gpaPath = try! PortalEndpoints.gpa(studentID: "student-1").url.path
        return RecordingTransport(responses: [
            PortalEndpoints.gradeSheet().url.path: [.success(gradeSheet)],
            "/student/for-std/grade/sheet/info/student-1": [.success(gradeOne), .success(gradeTwo)],
            gpaPath: [gpa],
            PortalEndpoints.courseTable().url.path: [.success(courseTable)],
            "/student/ws/semester/get/term-1": [.success(semester)],
            "/student/for-std/course-table/semester/term-1/print-data/student-1": [.success(printData)],
            "/student/ws/semester/get/term-2": [.success(nextSemester)],
            "/student/for-std/course-table/semester/term-2/print-data/student-1": [.success(nextPrintData)],
        ])
    }

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [])
    }
}

private final class StatusRecordingTransport: PortalCollectionTransport, @unchecked Sendable {
    private let data: Data
    private let statusCode: Int

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func send(_ request: StableHTTPCollectionRequest) async throws -> (Data, HTTPURLResponse) {
        (
            data,
            HTTPURLResponse(
                url: request.url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
