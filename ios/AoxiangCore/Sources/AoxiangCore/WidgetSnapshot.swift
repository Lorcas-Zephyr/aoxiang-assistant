import Foundation

public struct WidgetCourseSnapshot: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let teacher: String?
    public let location: String?
    public let dayOfWeek: Int?
    public let sections: [Int]

    public init(
        id: String,
        name: String,
        teacher: String? = nil,
        location: String? = nil,
        dayOfWeek: Int? = nil,
        sections: [Int] = []
    ) {
        self.id = id
        self.name = name
        self.teacher = teacher
        self.location = location
        self.dayOfWeek = dayOfWeek
        self.sections = sections
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
    public let gradeSummary: WidgetGradeSummary

    public init(
        generatedAtEpochMilliseconds: Int64,
        selectedSemesterName: String?,
        todayCourses: [WidgetCourseSnapshot],
        gradeSummary: WidgetGradeSummary
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAtEpochMilliseconds = generatedAtEpochMilliseconds
        self.selectedSemesterName = selectedSemesterName
        self.todayCourses = todayCourses
        self.gradeSummary = gradeSummary
    }

    public func validated() throws -> WidgetSnapshot {
        guard schemaVersion == Self.currentSchemaVersion,
              generatedAtEpochMilliseconds >= 0,
              gradeSummary.count >= 0,
              (gradeSummary.averageScore.map { $0.isFinite && (0.0...100.0).contains($0) } ?? true),
              (gradeSummary.gpa.map { $0.isFinite && (0.0...5.0).contains($0) } ?? true),
              todayCourses.allSatisfy({ course in
                  guard !course.id.isEmpty, !course.name.isEmpty,
                        course.sections.allSatisfy({ $0 > 0 }) else {
                      return false
                  }
                  return course.dayOfWeek.map { (1...7).contains($0) } ?? true
              }) else {
            throw OfflineDataError.invalidField("widget snapshot")
        }
        return self
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
        let courses = valid.courses.filter { course in
            guard course.semesterId == valid.selectedSemesterId, let activeWeek else { return false }
            return course.timeSlots.contains {
                $0.dayOfWeek == day
                    && OfflineScheduleService.isWeekActive(
                        activeWeek,
                        weekRange: $0.weekRange,
                        repeatRule: $0.repeatRule
                    )
            }
        }.map { course in
            let slot = course.timeSlots.first {
                $0.dayOfWeek == day
                    && OfflineScheduleService.isWeekActive(
                        activeWeek ?? 0,
                        weekRange: $0.weekRange,
                        repeatRule: $0.repeatRule
                    )
            }
            return WidgetCourseSnapshot(
                id: course.id,
                name: course.name,
                teacher: course.teacher ?? slot?.teacher,
                location: course.location ?? slot?.location,
                dayOfWeek: slot?.dayOfWeek,
                sections: slot?.classSections ?? []
            )
        }
        let scored = valid.grades.compactMap(\.score)
        let average = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)
        let gpaValues = valid.grades.compactMap(\.point)
        let computedGPA = gpaValues.isEmpty ? nil : gpaValues.reduce(0, +) / Double(gpaValues.count)
        return WidgetSnapshot(
            generatedAtEpochMilliseconds: Int64(now.timeIntervalSince1970 * 1000),
            selectedSemesterName: semester?.name,
            todayCourses: courses,
            gradeSummary: WidgetGradeSummary(count: valid.grades.count, averageScore: average, gpa: valid.gpa ?? computedGPA)
        )
    }
}
