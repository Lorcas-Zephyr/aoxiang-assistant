import Foundation
import XCTest
@testable import AoxiangCore

final class OfflineDataTests: XCTestCase {
    func testAppGroupCandidatesPreferSignedEntitlementOverStalePlist() {
        XCTAssertEqual(
            AoxiangSharedContainer.appGroupCandidates(
                configuredIdentifier: "group.old-team",
                entitledIdentifiers: ["group.new-team"]
            ),
            ["group.new-team"]
        )
    }

    func testAppGroupCandidatesFailClosedWhenSignedTargetDeclaresNoGroups() {
        XCTAssertEqual(
            AoxiangSharedContainer.appGroupCandidates(
                configuredIdentifier: "group.old-team",
                entitledIdentifiers: []
            ),
            []
        )
    }

    func testAppGroupCandidatesUseConfiguredValueWhenEntitlementsCannotBeInspected() {
        XCTAssertEqual(
            AoxiangSharedContainer.appGroupCandidates(
                configuredIdentifier: "group.team",
                entitledIdentifiers: nil
            ),
            ["group.team", AoxiangSharedContainer.defaultAppGroupIdentifier]
        )
    }

    func testImportsLegacyAndroidBackupAndNormalizesToCurrentState() throws {
        let legacy = """
        {"version":"2.0","exportDate":"2026-01-15","courses":[{"id":"course-1","name":"软件工程","semesterId":"semester-1","timeSlots":[{"weekRange":"1-17","repeatRule":"","dayOfWeek":2,"classSections":[1,2]}]}],"settings":{"semesters":[{"id":"semester-1","name":"2026 春季","startDate":"2026-02-23","endDate":"2026-07-05","weekCount":18,"sectionCount":13,"sectionTimes":[{"start":"08:30","end":"09:15"}]}],"themeColor":"#2F80ED","darkMode":false}}
        """.data(using: .utf8)!

        let state = try AndroidBackupImporter().importData(legacy)

        XCTAssertEqual(state.schemaVersion, 1)
        XCTAssertEqual(state.courses.map(\.id), ["course-1"])
        XCTAssertEqual(state.semesters.map(\.id), ["semester-1"])
        XCTAssertEqual(state.display.themeColor, "#2F80ED")
    }

    func testCurrentBackupRoundTripsWithoutLocalGradesOrSecrets() throws {
        let state = OfflineAppState(
            courses: [OfflineCourse(id: "course-1", name: "课程", semesterId: "term-1")],
            semesters: [OfflineSemester(id: "term-1", name: "学期", startDate: "2026-01-01", endDate: "2026-06-30")],
            selectedSemesterId: "term-1",
            display: OfflineDisplaySettings(themeColor: "#43A047", darkMode: true),
            grades: [OfflineGrade(course: "本地成绩", score: 90)]
        )
        let data = try AndroidBackupExporter().exportData(from: state, exportDate: Date(timeIntervalSince1970: 0))
        let text = String(decoding: data, as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("grades"))
        XCTAssertFalse(text.contains("password"))
        XCTAssertFalse(text.contains("cookie"))

        let imported = try AndroidBackupImporter().importData(data)
        XCTAssertTrue(imported.grades.isEmpty)
        XCTAssertEqual(imported.selectedSemesterId, "term-1")
        XCTAssertTrue(imported.display.darkMode)
    }

    func testPrivateGPAFieldIsBackwardCompatibleAndExcludedFromPortableBackup() throws {
        let legacy = """
        {"schemaVersion":1,"courses":[],"semesters":[],"selectedSemesterId":"","display":{"themeColor":"#2F80ED","darkMode":false},"grades":[],"electricityBalance":null}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(OfflineAppState.self, from: legacy)
        XCTAssertNil(decoded.gpa)

        let state = OfflineAppState(
            semesters: [OfflineSemester(id: "term-1", startDate: "2026-01-01", endDate: "2026-06-30")],
            selectedSemesterId: "term-1",
            gpa: 3.8,
            electricityBalance: 12
        )
        let backup = try AndroidBackupExporter().exportData(from: state)
        let object = try JSONSerialization.jsonObject(with: backup) as! [String: Any]
        let text = String(data: backup, encoding: .utf8)!
        XCTAssertNil(object["gpa"])
        XCTAssertNil(object["electricityBalance"])
        XCTAssertFalse(text.contains("3.8"))
        XCTAssertFalse(text.contains("12"))
    }

    func testAndroidScheduleBackupPreservesExistingPrivateGrades() throws {
        let privateGrade = OfflineGrade(
            id: "grade-1",
            course: "本地成绩",
            credits: 3,
            score: 91
        )
        let previous = OfflineAppState(
            courses: [OfflineCourse(id: "old-course", name: "旧课程", semesterId: "old-term")],
            semesters: [OfflineSemester(
                id: "old-term",
                startDate: "2026-01-01",
                endDate: "2026-06-30"
            )],
            selectedSemesterId: "old-term",
            grades: [privateGrade]
        )
        let store = InMemoryOfflineStateStore(value: previous)
        let controller = try OfflineDataController(store: store)
        let backup = try AndroidBackupExporter().exportData(from: OfflineAppState(
            courses: [OfflineCourse(id: "new-course", name: "新课程", semesterId: "new-term")],
            semesters: [OfflineSemester(
                id: "new-term",
                startDate: "2026-09-01",
                endDate: "2027-01-31"
            )],
            selectedSemesterId: "new-term"
        ))

        _ = try controller.importAndroidBackup(backup)

        XCTAssertEqual(controller.state.courses.map(\.id), ["new-course"])
        XCTAssertEqual(controller.state.selectedSemesterId, "new-term")
        XCTAssertEqual(controller.state.grades, [privateGrade])
        XCTAssertEqual(store.value?.grades, [privateGrade])
    }

    func testGradesUseSeparateLocalEnvelopeAndNeverWidenPortableBackup() throws {
        let grades = """
        {"schemaVersion":1,"items":[{"course":"软件工程","credits":3,"point":4,"score":95,"category":"课程","detail":"平时成绩"}]}
        """.data(using: .utf8)!
        let imported = try AndroidGradesImporter().importData(grades)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].course, "软件工程")
        XCTAssertEqual(imported[0].score, 95)

        let backup = try AndroidBackupExporter().exportData(from: OfflineAppState(grades: imported))
        XCTAssertFalse(String(decoding: backup, as: UTF8.self).contains("items"))
        XCTAssertFalse(String(decoding: backup, as: UTF8.self).contains("软件工程"))
    }

    func testDanglingCourseReferenceIsRejectedBeforeStoreMutation() throws {
        let json = """
        {"format":"aoxiang-assistant.schedule-backup","schemaVersion":1,"version":"2.0","courses":[{"id":"course-1","semesterId":"missing"}],"settings":{"semesters":[]}}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try AndroidBackupImporter().importData(json)) { error in
            XCTAssertEqual(error as? OfflineDataError, .danglingReference("missing"))
        }
    }

    func testUnknownNestedBackupFieldsAreRejectedInsteadOfSilentlyDropped() throws {
        let json = """
        {"format":"aoxiang-assistant.schedule-backup","schemaVersion":1,"version":"2.0","courses":[{"id":"course-1","semesterId":"term-1","futureField":"x"}],"settings":{"semesters":[{"id":"term-1","startDate":"2026-01-01","endDate":"2026-06-30"}]}}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try AndroidBackupImporter().importData(json)) { error in
            XCTAssertEqual(error as? OfflineDataError, .unknownField("course.futureField"))
        }
    }

    func testFailedEditKeepsPreviousState() throws {
        let old = OfflineAppState(
            courses: [OfflineCourse(id: "course-1", name: "原课程", semesterId: "term-1")],
            semesters: [OfflineSemester(id: "term-1", startDate: "2026-01-01", endDate: "2026-06-30")]
        )
        let store = InMemoryOfflineStateStore(value: old)
        let controller = try OfflineDataController(store: store)
        store.shouldFailWrites = true

        XCTAssertThrowsError(try controller.updateCourse(
            OfflineCourse(id: "course-1", name: "未保存", semesterId: "term-1")
        ))
        XCTAssertEqual(controller.state, old)
        XCTAssertEqual(store.value, old)
    }

    func testRecoveryControllerRefusesEditsUntilAValidBackupReplacesUnreadableState() throws {
        let store = InMemoryOfflineStateStore()
        let controller = OfflineDataController.recoveryController(store: store)

        XCTAssertThrowsError(try controller.addCourse(OfflineCourse(
            id: "course-1",
            name: "不能覆盖",
            semesterId: "term-1"
        ))) { error in
            XCTAssertEqual(error as? OfflineDataError, .recoveryRequired)
        }

        let backup = try AndroidBackupExporter().exportData(from: OfflineAppState(
            semesters: [OfflineSemester(
                id: "term-1",
                startDate: "2026-01-01",
                endDate: "2026-06-30"
            )],
            selectedSemesterId: "term-1"
        ))
        try controller.importAndroidBackup(backup)

        XCTAssertFalse(controller.isRecoveryRequired)
        XCTAssertNoThrow(try controller.addCourse(OfflineCourse(
            id: "course-1",
            name: "恢复后可编辑",
            semesterId: "term-1"
        )))
    }

    func testSnapshotIsReadOnlyAndContainsOnlySanitizedData() throws {
        let state = OfflineAppState(
            courses: [OfflineCourse(id: "course-1", name: "课程", semesterId: "term-1", timeSlots: [OfflineTimeSlot(dayOfWeek: 1)])],
            semesters: [OfflineSemester(id: "term-1", name: "学期", startDate: "2026-01-01", endDate: "2026-06-30")],
            selectedSemesterId: "term-1",
            grades: [OfflineGrade(course: "课程", point: 4, score: 90)],
            electricityBalance: 12.5
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = ISO8601DateFormatter().date(from: "2026-01-05T00:00:00Z")!
        let snapshot = try WidgetSnapshotBuilder().makeSnapshot(from: state, now: date, calendar: calendar)
        XCTAssertEqual(snapshot.todayCourses.map(\.id), ["course-1"])
        XCTAssertEqual(snapshot.gradeSummary.count, 1)
        XCTAssertEqual(snapshot.electricityBalance, 12.5)
        let data = try JSONEncoder().encode(snapshot)
        let text = String(decoding: data, as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("password"))
        XCTAssertFalse(text.contains("cookie"))
        XCTAssertFalse(text.contains("authentication"))
    }

    func testSnapshotExcludesOutOfRangeAndInactiveRepeatCourses() throws {
        let state = OfflineAppState(
            courses: [
                OfflineCourse(
                    id: "active",
                    name: "当前课程",
                    semesterId: "term-1",
                    timeSlots: [OfflineTimeSlot(weekRange: "1-2", dayOfWeek: 1)]
                ),
                OfflineCourse(
                    id: "later",
                    name: "后续课程",
                    semesterId: "term-1",
                    timeSlots: [OfflineTimeSlot(weekRange: "5", dayOfWeek: 1)]
                ),
                OfflineCourse(
                    id: "even",
                    name: "双周课程",
                    semesterId: "term-1",
                    timeSlots: [OfflineTimeSlot(weekRange: "1-2", repeatRule: .even, dayOfWeek: 1)]
                ),
            ],
            semesters: [OfflineSemester(id: "term-1", startDate: "2026-01-05", endDate: "2026-06-30")],
            selectedSemesterId: "term-1"
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = ISO8601DateFormatter().date(from: "2026-01-05T00:00:00Z")!
        let snapshot = try WidgetSnapshotBuilder().makeSnapshot(from: state, now: date, calendar: calendar)
        XCTAssertEqual(snapshot.todayCourses.map(\.id), ["active"])
    }

    func testWidgetSnapshotWithoutElectricityRemainsReadable() throws {
        let legacy = """
        {"schemaVersion":1,"generatedAtEpochMilliseconds":1,"selectedSemesterName":"学期","todayCourses":[],"gradeSummary":{"count":0,"averageScore":null,"gpa":null}}
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: legacy)

        XCTAssertNil(snapshot.electricityBalance)
        XCTAssertNoThrow(try snapshot.validated())
    }

    func testFileStoreUsesAtomicReplacementAndRejectsCorruptState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileOfflineStateStore(fileURL: url)
        let state = OfflineAppState(
            semesters: [OfflineSemester(id: "term-1", startDate: "2026-01-01", endDate: "2026-06-30")]
        )
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
        try Data("{bad".utf8).write(to: url)
        XCTAssertThrowsError(try store.load())
    }

    func testInvalidLocalGradeCannotBeValidatedOrPersisted() throws {
        let invalid = OfflineAppState(
            grades: [OfflineGrade(id: "grade-1", course: "课程", credits: 3, score: 120)]
        )
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? OfflineDataError, .invalidField("grade.score"))
        }
    }

    func testDuplicateLocalGradeIDsAreRejected() throws {
        let invalid = OfflineAppState(grades: [
            OfflineGrade(id: "same", course: "课程 A"),
            OfflineGrade(id: "same", course: "课程 B"),
        ])
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? OfflineDataError, .duplicateID("same"))
        }
    }

    func testGradeImportRejectsUnknownOrSensitiveFields() throws {
        let unknown = "[{\"course\":\"课程\",\"credits\":3,\"future\":true}]".data(using: .utf8)!
        XCTAssertThrowsError(try AndroidGradesImporter().importData(unknown)) { error in
            XCTAssertEqual(error as? OfflineDataError, .unknownField("grades[0].future"))
        }

        let secret = "[{\"course\":\"课程\",\"credits\":3,\"password\":\"x\"}]".data(using: .utf8)!
        XCTAssertThrowsError(try AndroidGradesImporter().importData(secret)) { error in
            XCTAssertEqual(error as? OfflineDataError, .sensitiveField("password"))
        }
    }

    func testGradeImportReplacesOnlyGradesAndPreservesSchedule() throws {
        let old = OfflineAppState(
            courses: [OfflineCourse(id: "course", name: "课", semesterId: "term")],
            semesters: [OfflineSemester(id: "term", startDate: "2026-01-01", endDate: "2026-06-30")],
            selectedSemesterId: "term"
        )
        let store = InMemoryOfflineStateStore(value: old)
        let controller = try OfflineDataController(store: store)
        let data = "[{\"course\":\"课\",\"credits\":3,\"score\":90}]".data(using: .utf8)!

        try controller.importAndroidGrades(data)

        XCTAssertEqual(controller.state.courses.map(\.id), ["course"])
        XCTAssertEqual(controller.state.grades.map(\.course), ["课"])
    }

    func testDefaultScheduleCalendarUsesShanghaiBusinessTimezone() throws {
        let state = OfflineAppState(
            courses: [OfflineCourse(
                id: "course-1",
                name: "周二课程",
                semesterId: "term-1",
                timeSlots: [OfflineTimeSlot(dayOfWeek: 2)]
            )],
            semesters: [OfflineSemester(
                id: "term-1",
                startDate: "2026-01-05",
                endDate: "2026-06-30"
            )],
            selectedSemesterId: "term-1"
        )
        // 2026-01-05 16:30 UTC is already Tuesday in Asia/Shanghai.
        let date = ISO8601DateFormatter().date(from: "2026-01-05T16:30:00Z")!
        let snapshot = try WidgetSnapshotBuilder().makeSnapshot(from: state, now: date)

        XCTAssertEqual(snapshot.todayCourses.map(\.id), ["course-1"])
    }

    func testWidgetSnapshotValidationRejectsInvalidSummaryAndSections() {
        let invalidSummary = WidgetSnapshot(
            generatedAtEpochMilliseconds: 1,
            selectedSemesterName: "学期",
            todayCourses: [],
            gradeSummary: WidgetGradeSummary(count: 1, averageScore: 101, gpa: nil)
        )
        XCTAssertThrowsError(try invalidSummary.validated())

        let invalidElectricity = WidgetSnapshot(
            generatedAtEpochMilliseconds: 1,
            selectedSemesterName: "学期",
            todayCourses: [],
            gradeSummary: WidgetGradeSummary(count: 0, averageScore: nil, gpa: nil),
            electricityBalance: -1
        )
        XCTAssertThrowsError(try invalidElectricity.validated())

        let invalidCourse = WidgetSnapshot(
            generatedAtEpochMilliseconds: 1,
            selectedSemesterName: "学期",
            todayCourses: [WidgetCourseSnapshot(
                id: "course-1",
                name: "课程",
                dayOfWeek: 8,
                sections: [0]
            )],
            gradeSummary: WidgetGradeSummary(count: 0, averageScore: nil, gpa: nil)
        )
        XCTAssertThrowsError(try invalidCourse.validated())
    }

    func testUnavailableWidgetSnapshotStoreFailsClosed() {
        let store = UnavailableWidgetSnapshotStore()
        let snapshot = WidgetSnapshot(
            generatedAtEpochMilliseconds: 1,
            selectedSemesterName: nil,
            todayCourses: [],
            gradeSummary: WidgetGradeSummary(count: 0, averageScore: nil, gpa: nil)
        )

        XCTAssertThrowsError(try store.read()) { error in
            XCTAssertEqual(error as? OfflineDataError, .sharedContainerUnavailable)
        }
        XCTAssertThrowsError(try store.write(snapshot)) { error in
            XCTAssertEqual(error as? OfflineDataError, .sharedContainerUnavailable)
        }
    }

    func testSharedContainerFactoryNeverFallsBackOnNonIOSHost() throws {
        #if !os(iOS)
        let store = AoxiangSharedContainer.widgetSnapshotStore()
        XCTAssertTrue(store is UnavailableWidgetSnapshotStore)
        XCTAssertThrowsError(try store.read()) { error in
            XCTAssertEqual(error as? OfflineDataError, .sharedContainerUnavailable)
        }
        #endif
    }
}
