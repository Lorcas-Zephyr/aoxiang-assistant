import XCTest
@testable import AoxiangCore

final class OfflineDomainServiceTests: XCTestCase {
    func testRetakeKeepsHighestScoreAndPreservesWinningRecord() {
        let result = OfflineGradeService.keepHighest([
            OfflineGrade(id: "first", course: "  操作系统 ", point: 2.3, score: 72),
            OfflineGrade(id: "retake", course: "操作系统", point: 4, score: 91),
            OfflineGrade(id: "network", course: "计算机网络", point: 3.7, score: 88),
        ])
        XCTAssertEqual(result.map(\.id), ["retake", "network"])
    }

    func testGpaUsesValidApiBeforePortraitFallback() {
        XCTAssertEqual(OfflineGradeService.selectedGPA(api: 3.76, portrait: 3.42), 3.76)
        XCTAssertEqual(OfflineGradeService.selectedGPA(api: nil, portrait: 3.42), 3.42)
        XCTAssertNil(OfflineGradeService.selectedGPA(api: -1, portrait: nil))
    }

    func testOnlineCoursesCanBeFilteredWithoutDroppingOfflineCourse() {
        let state = OfflineAppState(
            courses: [
                OfflineCourse(id: "online", name: "线上", semesterId: "term", location: "线上教室"),
                OfflineCourse(id: "offline", name: "线下", semesterId: "term", location: "长安校区 B202"),
            ],
            semesters: [OfflineSemester(id: "term", startDate: "2026-01-01", endDate: "2026-06-30")],
            selectedSemesterId: "term"
        )
        XCTAssertEqual(OfflineScheduleService.courses(in: state, includeOnline: false).map(\.id), ["offline"])
    }

    func testFriendshipSectionTimeUsesStableWinterSchedule() {
        let semester = OfflineSemester(id: "term", startDate: "2026-01-01", endDate: "2026-06-30")
        XCTAssertEqual(
            OfflineScheduleService.sectionTime(7, semester: semester, location: "友谊校区")?.start,
            "14:00"
        )
    }

    func testFriendshipSectionTimeUsesSummerScheduleWhenSemesterStartsInSummer() {
        let semester = OfflineSemester(id: "term", startDate: "2026-08-17", endDate: "2026-12-20")
        XCTAssertEqual(
            OfflineScheduleService.sectionTime(7, semester: semester, location: "友谊校区")?.start,
            "14:30"
        )
        XCTAssertEqual(
            OfflineScheduleService.sectionTime(8, semester: semester, location: "友谊校区")?.end,
            "16:20"
        )
    }

    func testCoursesOnDayHonorsWeekRangeAndOddEvenRules() {
        let semester = OfflineSemester(id: "term", startDate: "2026-08-31", endDate: "2027-01-10")
        let state = OfflineAppState(
            courses: [
                OfflineCourse(
                    id: "all",
                    name: "每周",
                    semesterId: "term",
                    timeSlots: [OfflineTimeSlot(weekRange: "1-3", dayOfWeek: 1)]
                ),
                OfflineCourse(
                    id: "odd",
                    name: "单周",
                    semesterId: "term",
                    timeSlots: [OfflineTimeSlot(weekRange: "1-3", repeatRule: .odd, dayOfWeek: 1)]
                ),
                OfflineCourse(
                    id: "later",
                    name: "后续",
                    semesterId: "term",
                    timeSlots: [OfflineTimeSlot(weekRange: "5", dayOfWeek: 1)]
                ),
            ],
            semesters: [semester],
            selectedSemesterId: "term"
        )

        XCTAssertEqual(
            OfflineScheduleService.courses(on: 1, week: 1, in: state).map(\.id),
            ["all", "odd"]
        )
        XCTAssertEqual(
            OfflineScheduleService.courses(on: 1, week: 2, in: state).map(\.id),
            ["all"]
        )
    }

    func testMeetingsOnDayKeepsMultipleSlotsForTheSameCourseInSectionOrder() {
        let state = OfflineAppState(
            courses: [
                OfflineCourse(
                    id: "math",
                    name: "数学",
                    semesterId: "term",
                    timeSlots: [
                        OfflineTimeSlot(weekRange: "1-3", dayOfWeek: 1, classSections: [7, 8]),
                        OfflineTimeSlot(weekRange: "1-3", dayOfWeek: 1, classSections: [1, 2]),
                        OfflineTimeSlot(weekRange: "1-3", repeatRule: .odd, dayOfWeek: 1, classSections: [11, 12]),
                    ]
                ),
            ],
            semesters: [OfflineSemester(id: "term", startDate: "2026-08-31", endDate: "2027-01-10")],
            selectedSemesterId: "term"
        )

        let weekOne = OfflineScheduleService.meetings(on: 1, week: 1, in: state)
        XCTAssertEqual(weekOne.map { $0.course.name }, ["数学", "数学", "数学"])
        XCTAssertEqual(weekOne.map { $0.timeSlot.classSections }, [[1, 2], [7, 8], [11, 12]])
        XCTAssertEqual(
            OfflineScheduleService.meetings(on: 1, week: 2, in: state).map { $0.timeSlot.classSections },
            [[1, 2], [7, 8]]
        )
        XCTAssertTrue(OfflineScheduleService.meetings(on: 2, week: 1, in: state).isEmpty)
    }
}
