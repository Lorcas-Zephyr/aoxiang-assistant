import Foundation
import XCTest
@testable import AoxiangCore

final class PortalCollectionParserTests: XCTestCase {
    func testGradeAPIParsesPublishedRowsAndGPA() throws {
        let input = try fixtureData("grades-api-response/input.json")
        let result = try PortalCollectionParsers.parseGradeAPI(input)

        XCTAssertEqual(result.grades.count, 2)
        XCTAssertEqual(result.grades.map(\.course), ["软件工程", "课程名称回退"])
        XCTAssertEqual(result.grades[0].credits, 3.0)
        XCTAssertEqual(result.grades[0].point, 4.0)
        XCTAssertEqual(result.grades[0].score, 95.0)
        XCTAssertEqual(result.grades[0].detail, "平时成绩:88 期末成绩:95")
        XCTAssertEqual(result.apiGPA ?? -1, 3.76, accuracy: 0.0001)
    }

    func testPortraitHTMLSuppliesGPAWhenAPIIsMissing() throws {
        let input = try fixtureData("grades-gpa-portrait-fallback/input.json")
        let html = try fixtureText("grades-gpa-portrait-fallback/portrait.html")
        let result = try PortalCollectionParsers.parseGradeAPI(input)

        XCTAssertNil(result.apiGPA)
        XCTAssertEqual(PortalCollectionParsers.parsePortraitGPA(html) ?? -1, 3.42, accuracy: 0.0001)
        XCTAssertEqual(
            PortalCollectionParsers.selectGPA(api: result.apiGPA, portrait: 3.42) ?? -1,
            3.42,
            accuracy: 0.0001
        )
    }

    func testSameNameRetakeKeepsHighestScore() throws {
        let input = try fixtureData("grades-retake-same-name/input.json")
        let records = try PortalCollectionParsers.parseGradeAPIRecords(input)
        let best = PortalCollectionParsers.keepHighest(records)

        XCTAssertEqual(best.count, 2)
        XCTAssertEqual(best.first(where: { $0.course.trimmingCharacters(in: .whitespacesAndNewlines) == "操作系统" })?.score, 91.0)
    }

    func testScheduleTextPreservesMixedRepeatRulesAndNonContiguousWeeks() throws {
        let mixed = PortalCollectionParsers.parseScheduleText(
            "4~6（双）,7~9（单）周 周六 1-4节"
        )
        XCTAssertEqual(mixed.map(\.weekRange), ["4-6", "7-9"])
        XCTAssertEqual(mixed.map(\.repeatRule), [.even, .odd])
        XCTAssertEqual(mixed.map(\.dayOfWeek), [6, 6])
        XCTAssertEqual(mixed.map(\.classSections), [[1, 2, 3, 4], [1, 2, 3, 4]])

        let sparse = PortalCollectionParsers.parseScheduleText("2,4,7周 星期三 3-4节")
        XCTAssertEqual(sparse.map(\.weekRange), ["2", "4", "7"])
        XCTAssertTrue(sparse.allSatisfy { $0.repeatRule == .all && $0.dayOfWeek == 3 })
    }

    func testSchedulePayloadHandlesEmptyDatesTeachersLocationsAndOnlineFilter() throws {
        let emptyInput = try fixtureData("schedule-empty/input.json")
        let empty = try PortalCollectionParsers.parseSchedulePayload(emptyInput)
        XCTAssertEqual(empty.courses.count, 0)
        XCTAssertEqual(empty.semesters.first?.endDate, "2026-07-19")

        let meetingInput = try fixtureData("schedule-teachers-locations/input.json")
        let meeting = try PortalCollectionParsers.parseSchedulePayload(meetingInput)
        XCTAssertEqual(meeting.courses.count, 1)
        XCTAssertEqual(meeting.courses[0].teacher, "张三、李四、王五")
        XCTAssertEqual(meeting.courses[0].location, "友谊校区 公字楼 A101\n长安校区 教西 B201")
        XCTAssertEqual(meeting.courses[0].timeSlots.count, 2)
        XCTAssertEqual(meeting.courses[0].timeSlots.map(\.teacher), ["张三、李四", "李四、王五"])
        XCTAssertEqual(meeting.courses[0].timeSlots.map(\.location), [
            "友谊校区 公字楼 A101", "长安校区 教西 B201"
        ])

        let onlineInput = try fixtureData("schedule-online-filter/input.json")
        let online = try PortalCollectionParsers.parseSchedulePayload(onlineInput)
        XCTAssertEqual(online.courses.map(\.name), ["线下数据结构"])
    }

    func testScheduleSemesterSelectionFollowsAndroidCurrentNextAndLatestRules() {
        let semesters = [
            PortalCollectionParsers.ScheduleSemesterCandidate(
                id: "future", name: "2027 春", startDate: "2027-02-22", endDate: "2027-07-18"
            ),
            PortalCollectionParsers.ScheduleSemesterCandidate(
                id: "current", name: "2026 秋", startDate: "2026-08-31", endDate: "2027-01-10"
            ),
            PortalCollectionParsers.ScheduleSemesterCandidate(
                id: "past", name: "2026 春", startDate: "2026-02-23", endDate: "2026-07-19"
            ),
            PortalCollectionParsers.ScheduleSemesterCandidate(
                id: "undated", name: "无日期", startDate: "not-a-date", endDate: nil
            ),
        ]

        let inCurrent = PortalCollectionParsers.selectScheduleSemester(
            from: semesters, today: "2026-09-08"
        )
        XCTAssertEqual(inCurrent?.ordered.map(\.id), ["past", "current", "future"])
        XCTAssertEqual(inCurrent?.initial.id, "current")

        let beforeAll = PortalCollectionParsers.selectScheduleSemester(
            from: semesters, today: "2025-09-01"
        )
        XCTAssertEqual(beforeAll?.initial.id, "past")

        let afterAll = PortalCollectionParsers.selectScheduleSemester(
            from: semesters, today: "2028-01-01"
        )
        XCTAssertEqual(afterAll?.initial.id, "future")

        let openEnded = PortalCollectionParsers.selectScheduleSemester(
            from: [
                PortalCollectionParsers.ScheduleSemesterCandidate(
                    id: "open", name: "开放学期", startDate: "2026-01-01", endDate: nil
                ),
            ],
            today: "2028-01-01"
        )
        XCTAssertEqual(openEnded?.initial.id, "open")
    }

    func testDiscoverScheduleSemestersReadsAndroidEmbeddedJSON() {
        let html = #"<script>const semesters = JSON.parse('[{"id":"term-1","name":"2026 春","startDate":"2026-02-23","endDate":"2026-07-19"},{"id":"term-2","name":"2026 秋","startDate":"2026-08-31"}]');</script>"#

        let semesters = PortalCollectionParsers.discoverScheduleSemesters(from: html)

        XCTAssertEqual(semesters.map(\.id), ["term-1", "term-2"])
        XCTAssertEqual(semesters.map(\.startDate), ["2026-02-23", "2026-08-31"])
        XCTAssertEqual(semesters[0].endDate, "2026-07-19")
        XCTAssertEqual(PortalCollectionParsers.discoverSemesterIDs(from: html), ["term-1", "term-2"])
    }

    func testEffectiveScheduleEndDateKeepsTwoWeekMinimumForEmptyPrintData() throws {
        let input = try fixtureData("schedule-empty/input.json")

        XCTAssertEqual(
            PortalCollectionParsers.effectiveScheduleEndDate(
                startDate: "2026-07-06", printData: input
            ),
            "2026-07-19"
        )
    }

    func testElectricityParserAcceptsFiniteNonnegativeBalanceOnly() throws {
        let input = try fixtureData("electricity-anomaly/input.json")
        let object = try JSONSerialization.jsonObject(with: input) as! [String: Any]
        let valid = try JSONSerialization.data(withJSONObject: object["valid"] as! [String: Any])
        let negative = try JSONSerialization.data(withJSONObject: object["negative"] as! [String: Any])
        let malformed = try JSONSerialization.data(withJSONObject: object["malformed"] as! [String: Any])

        XCTAssertEqual(PortalCollectionParsers.parseElectricityBalance(valid) ?? -1, 18.52, accuracy: 0.0001)
        XCTAssertNil(PortalCollectionParsers.parseElectricityBalance(negative))
        XCTAssertNil(PortalCollectionParsers.parseElectricityBalance(malformed))
    }

    func testVisibleEducationPayloadOnlyNeedsSanitizedFields() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "phase": "success",
            "grades": [[
                "course": "软件工程",
                "credits": 3,
                "point": 4.0,
                "score": 95,
                "category": "课程",
                "detail": "期末成绩 95",
            ]],
            "gpa": 3.76,
            "schedule": [
                "semester": [
                    "id": "term-1",
                    "name": "2026 秋",
                    "startDate": "2026-08-31",
                    "endDate": "2027-01-10",
                ],
                "activities": [[
                    "name": "软件工程",
                    "code": "SE-101",
                    "credits": 3,
                    "weekday": 1,
                    "startUnit": 1,
                    "endUnit": 2,
                    "weekIndexes": [1, 2, 3],
                    "teachers": ["张老师"],
                    "campus": "长安",
                    "building": "A",
                    "room": "101",
                ]],
            ],
        ])

        let result = try PortalCollectionParsers.parseVisibleEducation(data)

        XCTAssertEqual(result.grades.map(\.course), ["软件工程"])
        XCTAssertEqual(result.gpa ?? -1, 3.76, accuracy: 0.0001)
        XCTAssertEqual(result.schedule.semesters.map(\.id), ["term-1"])
        XCTAssertEqual(result.schedule.courses.first?.teacher, "张老师")
        XCTAssertEqual(result.schedule.courses.first?.location, "长安 A 101")
    }

    private func fixtureData(_ relativePath: String) throws -> Data {
        try Data(contentsOf: fixtureRoot().appendingPathComponent(relativePath))
    }

    private func fixtureText(_ relativePath: String) throws -> String {
        try String(decoding: fixtureData(relativePath), as: UTF8.self)
    }

    private func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contract-fixtures/golden/v1", isDirectory: true)
    }
}
