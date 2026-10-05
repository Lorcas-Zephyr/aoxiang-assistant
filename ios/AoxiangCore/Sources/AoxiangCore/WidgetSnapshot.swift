import Foundation

public struct WidgetCourseSnapshot: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let teacher: String?
    public let location: String?
    public let dayOfWeek: Int?
    public let sections: [Int]
    /// Stable display range derived from the selected semester's section table.
    /// It is optional so snapshots written before the week-view widgets remain
    /// readable without migration data.
    public let timeRange: String?

    public init(
        id: String,
        name: String,
        teacher: String? = nil,
        location: String? = nil,
        dayOfWeek: Int? = nil,
        sections: [Int] = [],
        timeRange: String? = nil
    ) {
        self.id = id
        self.name = name
        self.teacher = teacher
        self.location = location
        self.dayOfWeek = dayOfWeek
        self.sections = sections
        self.timeRange = timeRange
    }
}

public struct WidgetGradeSummary: Codable, Equatable {
    public let count: Int
    public let averageScore: Double?
    public let gpa: Double?

    public init(count: Int, averageScore: Double?, gpa: Double?) {
        self.count = count
        self.averageScore = averageScore
        self.gpa = gpa
    }
}

/// Sanitized, versioned data written by the main app. No credentials, cookies,
/// network clients or authentication state can be represented by this type.
public struct WidgetSnapshot: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let generatedAtEpochMilliseconds: Int64
    public let selectedSemesterName: String?
    public let todayCourses: [WidgetCourseSnapshot]
    /// Courses for the full active academic week. This is separate from
    /// `todayCourses` so small daily widgets do not need to reconstruct a week.
    public let activeWeek: Int?
    public let weekCourses: [WidgetCourseSnapshot]
    public let gradeSummary: WidgetGradeSummary
    /// Optional so snapshots written by the previous schema remain readable.
    /// The value is still sanitized and never carries credentials or session
    /// metadata.
    public let electricityBalance: Double?

    public init(
        generatedAtEpochMilliseconds: Int64,
        selectedSemesterName: String?,
        todayCourses: [WidgetCourseSnapshot],
        gradeSummary: WidgetGradeSummary,
        electricityBalance: Double? = nil,
        activeWeek: Int? = nil,
        weekCourses: [WidgetCourseSnapshot] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAtEpochMilliseconds = generatedAtEpochMilliseconds
        self.selectedSemesterName = selectedSemesterName
        self.todayCourses = todayCourses
        self.activeWeek = activeWeek
        self.weekCourses = weekCourses
        self.gradeSummary = gradeSummary
        self.electricityBalance = electricityBalance
    }

    public static func empty(now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAtEpochMilliseconds: max(0, Int64(now.timeIntervalSince1970 * 1000)),
            selectedSemesterName: nil,
            todayCourses: [],
            gradeSummary: WidgetGradeSummary(count: 0, averageScore: nil, gpa: nil),
            electricityBalance: nil,
            activeWeek: nil,
            weekCourses: []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAtEpochMilliseconds, selectedSemesterName,
             todayCourses, activeWeek, weekCourses, gradeSummary, electricityBalance
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        generatedAtEpochMilliseconds = try values.decode(Int64.self, forKey: .generatedAtEpochMilliseconds)
        selectedSemesterName = try values.decodeIfPresent(String.self, forKey: .selectedSemesterName)
        todayCourses = try values.decodeIfPresent([WidgetCourseSnapshot].self, forKey: .todayCourses) ?? []
        activeWeek = try values.decodeIfPresent(Int.self, forKey: .activeWeek)
        weekCourses = try values.decodeIfPresent([WidgetCourseSnapshot].self, forKey: .weekCourses) ?? []
        gradeSummary = try values.decode(WidgetGradeSummary.self, forKey: .gradeSummary)
        electricityBalance = try values.decodeIfPresent(Double.self, forKey: .electricityBalance)
    }

    public func validated() throws -> WidgetSnapshot {
        guard schemaVersion == Self.currentSchemaVersion,
              generatedAtEpochMilliseconds >= 0,
              gradeSummary.count >= 0,
              (gradeSummary.averageScore.map { $0.isFinite && (0.0...100.0).contains($0) } ?? true),
              (gradeSummary.gpa.map { $0.isFinite && (0.0...5.0).contains($0) } ?? true),
              (electricityBalance.map { $0.isFinite && (0.0..<100000.0).contains($0) } ?? true),
              todayCourses.allSatisfy({ course in
                  Self.validCourse(course)
              }),
              weekCourses.allSatisfy({ course in
                  Self.validCourse(course)
              }) else {
            throw OfflineDataError.invalidField("widget snapshot")
        }
        return self
    }

    private static func validCourse(_ course: WidgetCourseSnapshot) -> Bool {
        guard !course.id.isEmpty, !course.name.isEmpty,
              course.sections.allSatisfy({ $0 > 0 }) else {
            return false
        }
        if let timeRange = course.timeRange, !timeRange.isEmpty {
            guard timeRange.range(of: #"^\d{2}:\d{2}-\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
                return false
            }
        }
        return course.dayOfWeek.map { (1...7).contains($0) } ?? true
    }
}

public protocol WidgetSnapshotReader {
    func read() throws -> WidgetSnapshot?
}

public protocol WidgetSnapshotWriter {
    func write(_ snapshot: WidgetSnapshot) throws
}

/// A deliberately narrow storage boundary shared by the main app and Widget.
/// Production code must obtain this only from `AoxiangSharedContainer` so a
/// missing App Group cannot be replaced by a private sandbox location.
public protocol WidgetSnapshotStore: WidgetSnapshotReader, WidgetSnapshotWriter {}

/// A snapshot commit can be rolled back when a companion status record fails
/// to persist. This is the cross-file transaction seam used by background
/// synchronization; callers never need to know the physical file layout.
public protocol ReversibleWidgetSnapshotStore: WidgetSnapshotStore {
    func restore(_ snapshot: WidgetSnapshot?) throws
}

public final class FileWidgetSnapshotStore: ReversibleWidgetSnapshotStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func read() throws -> WidgetSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(WidgetSnapshot.self, from: data).validated()
        } catch let error as OfflineDataError {
            throw error
        } catch {
            throw OfflineDataError.snapshotUnavailable
        }
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        let valid = try snapshot.validated()
        do {
            let parent = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(valid)
            let temporaryURL = parent.appendingPathComponent(".widget-\(UUID().uuidString).tmp")
            defer { try? fileManager.removeItem(at: temporaryURL) }
            try data.write(to: temporaryURL, options: [.atomic])
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch let error as OfflineDataError {
            throw error
        } catch {
            throw OfflineDataError.persistenceFailed(error.localizedDescription)
        }
    }

    public func restore(_ snapshot: WidgetSnapshot?) throws {
        if let snapshot {
            try write(snapshot)
            return
        }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw OfflineDataError.persistenceFailed(error.localizedDescription)
        }
    }
}

public struct WidgetSnapshotBuilder {
    public init() {}

    private struct ActiveCourseSlot {
        let course: OfflineCourse
        let slot: OfflineTimeSlot
        let identity: String
    }

    public func makeSnapshot(
        from state: OfflineAppState,
        now: Date = Date(),
        calendar: Calendar = OfflineDatePolicy.businessCalendar
    ) throws -> WidgetSnapshot {
        let valid = try state.validated()
        let semester = valid.semesters.first { $0.id == valid.selectedSemesterId }
        // Calendar weekday is Sunday=1; the shared contract uses Monday=1...Sunday=7.
        let weekday = calendar.component(.weekday, from: now)
        let day = weekday == 1 ? 7 : weekday - 1
        let activeWeek = semester.flatMap {
            OfflineScheduleService.academicWeek(for: now, semester: $0, calendar: calendar)
        }
        let activeSlots = valid.courses.flatMap { course -> [ActiveCourseSlot] in
            guard course.semesterId == valid.selectedSemesterId, let activeWeek else { return [] }
            return course.timeSlots
                .filter { slot in
                    OfflineScheduleService.isWeekActive(
                        activeWeek,
                        weekRange: slot.weekRange,
                        repeatRule: slot.repeatRule
                    )
                }
                .map { slot in
                    ActiveCourseSlot(course: course, slot: slot, identity: Self.slotIdentity(slot))
                }
        }.sorted {
            ($0.slot.dayOfWeek, $0.slot.classSections.min() ?? Int.max, $0.course.name, $0.course.id, $0.identity) <
            ($1.slot.dayOfWeek, $1.slot.classSections.min() ?? Int.max, $1.course.name, $1.course.id, $1.identity)
        }
        var occurrenceByIdentity: [String: Int] = [:]
        let activeWeekCourses = activeSlots.compactMap { activeSlot -> WidgetCourseSnapshot? in
            let course = activeSlot.course
            let slot = activeSlot.slot
            let firstSection = slot.classSections.min() ?? 0
            let lastSection = slot.classSections.max() ?? 0
            let first = OfflineScheduleService.sectionTime(firstSection, semester: semester ?? valid.semesters.first ?? OfflineSemester(id: "", startDate: "1970-01-01", endDate: "1970-01-01"), location: course.location ?? slot.location)
            let last = OfflineScheduleService.sectionTime(lastSection, semester: semester ?? valid.semesters.first ?? OfflineSemester(id: "", startDate: "1970-01-01", endDate: "1970-01-01"), location: course.location ?? slot.location)
            let timeRange: String? = if let first, let last { "\(first.start)-\(last.end)" } else { nil }
            let occurrenceKey = "\(Self.encodedIDComponent(course.id)).\(activeSlot.identity)"
            let occurrence = (occurrenceByIdentity[occurrenceKey] ?? 0) + 1
            occurrenceByIdentity[occurrenceKey] = occurrence
            let id: String
            if course.timeSlots.count == 1 {
                // Preserve the pre-week-widget ID for the common one-slot case.
                id = course.id
            } else {
                let baseID = "course.\(Self.encodedIDComponent(course.id)).slot.\(activeSlot.identity)"
                id = baseID + (occurrence > 1 ? ".duplicate.\(occurrence)" : "")
            }
            return WidgetCourseSnapshot(
                id: id,
                name: course.name,
                teacher: course.teacher ?? slot.teacher,
                location: course.location ?? slot.location,
                dayOfWeek: slot.dayOfWeek,
                sections: slot.classSections,
                timeRange: timeRange
            )
        }
        let courses = activeWeekCourses.filter { $0.dayOfWeek == day }
        let scored = valid.grades.compactMap(\.score)
        let average = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)
        let gpaValues = valid.grades.compactMap(\.point)
        let computedGPA = gpaValues.isEmpty ? nil : gpaValues.reduce(0, +) / Double(gpaValues.count)
        return WidgetSnapshot(
            generatedAtEpochMilliseconds: Int64(now.timeIntervalSince1970 * 1000),
            selectedSemesterName: semester?.name,
            todayCourses: courses,
            gradeSummary: WidgetGradeSummary(count: valid.grades.count, averageScore: average, gpa: valid.gpa ?? computedGPA),
            electricityBalance: valid.electricityBalance,
            activeWeek: activeWeek,
            weekCourses: activeWeekCourses
        )
    }

    private static func slotIdentity(_ slot: OfflineTimeSlot) -> String {
        let sections = slot.classSections.sorted().map(String.init).joined(separator: ",")
        return [
            slot.dayOfWeek.description,
            sections,
            slot.weekRange,
            slot.repeatRule.rawValue,
            slot.teacher ?? "",
            slot.location ?? "",
        ].map(encodedIDComponent).joined(separator: ".")
    }

    private static func encodedIDComponent(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
