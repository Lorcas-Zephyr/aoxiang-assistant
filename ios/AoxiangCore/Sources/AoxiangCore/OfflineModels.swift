import Foundation

public enum OfflineDataError: Error, Equatable {
    case emptyBackup
    case malformedBackup(String)
    case unsupportedFormat(String)
    case unsupportedSchemaVersion(Int)
    case unsupportedLegacyVersion(String)
    case missingField(String)
    case invalidField(String)
    case unknownField(String)
    case sensitiveField(String)
    case duplicateID(String)
    case danglingReference(String)
    case invalidEnum(String)
    case invalidDate(String)
    case invalidTime(String)
    case persistenceFailed(String)
    case recoveryRequired
    case snapshotUnavailable
    case sharedContainerUnavailable
}

extension OfflineDataError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyBackup: return "Backup is empty"
        case .malformedBackup(let value): return "Backup is malformed: \(value)"
        case .unsupportedFormat(let value): return "Unsupported backup format: \(value)"
        case .unsupportedSchemaVersion(let value): return "Unsupported backup schema version: \(value)"
        case .unsupportedLegacyVersion(let value): return "Unsupported legacy backup version: \(value)"
        case .missingField(let value): return "Missing backup field: \(value)"
        case .invalidField(let value): return "Invalid backup field: \(value)"
        case .unknownField(let value): return "Unsupported backup field: \(value)"
        case .sensitiveField(let value): return "Sensitive backup field is not portable: \(value)"
        case .duplicateID(let value): return "Duplicate identifier: \(value)"
        case .danglingReference(let value): return "Dangling reference: \(value)"
        case .invalidEnum(let value): return "Unsupported enum value: \(value)"
        case .invalidDate(let value): return "Invalid date: \(value)"
        case .invalidTime(let value): return "Invalid time: \(value)"
        case .persistenceFailed(let value): return "Persistence failed: \(value)"
        case .recoveryRequired: return "Local data must be recovered from a valid backup before editing"
        case .snapshotUnavailable: return "Widget snapshot is unavailable"
        case .sharedContainerUnavailable:
            return "Widget shared container is unavailable; no private fallback will be used"
        }
    }
}

public enum OfflineRepeatRule: String, Codable, Equatable, CaseIterable {
    case all = ""
    case odd = "仅单周"
    case even = "仅双周"

    public init(wireValue: String?) throws {
        let value = wireValue ?? ""
        guard let rule = Self(rawValue: value) else {
            throw OfflineDataError.invalidEnum("repeatRule=\(value)")
        }
        self = rule
    }
}

public enum OfflineAssessmentMethod: String, Codable, Equatable, CaseIterable {
    case exam = "考试"
    case inspection = "考察"
    case pnp = "PnP"

    public init(wireValue: String?) throws {
        guard let value = wireValue else {
            throw OfflineDataError.invalidEnum("assessmentMethod=null")
        }
        guard let method = Self(rawValue: value) else {
            throw OfflineDataError.invalidEnum("assessmentMethod=\(value)")
        }
        self = method
    }
}

public struct OfflineSectionTime: Codable, Equatable {
    public var start: String
    public var end: String

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        start = try values.decode(String.self, forKey: .start)
        end = try values.decode(String.self, forKey: .end)
        try Self.validateTime(start)
        try Self.validateTime(end)
    }

    public static func validateTime(_ value: String) throws {
        guard value.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil,
              let hour = Int(value.prefix(2)), let minute = Int(value.suffix(2)),
              hour <= 23, minute <= 59 else {
            throw OfflineDataError.invalidTime(value)
        }
    }

    private enum CodingKeys: String, CodingKey { case start, end }
}

public struct OfflineTimeSlot: Codable, Equatable {
    public var weekRange: String
    public var repeatRule: OfflineRepeatRule
    public var dayOfWeek: Int
    public var classSections: [Int]
    public var teacher: String?
    public var location: String?

    public init(
        weekRange: String = "1-17",
        repeatRule: OfflineRepeatRule = .all,
        dayOfWeek: Int = 1,
        classSections: [Int] = [1, 2],
        teacher: String? = nil,
        location: String? = nil
    ) {
        self.weekRange = weekRange
        self.repeatRule = repeatRule
        self.dayOfWeek = dayOfWeek
        self.classSections = classSections
        self.teacher = teacher
        self.location = location
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        weekRange = try values.decodeIfPresent(String.self, forKey: .weekRange) ?? "1-17"
        let wireRule = try values.decodeIfPresent(String.self, forKey: .repeatRule)
        repeatRule = try OfflineRepeatRule(wireValue: wireRule)
        dayOfWeek = try values.decodeIfPresent(Int.self, forKey: .dayOfWeek) ?? 1
        classSections = try values.decodeIfPresent([Int].self, forKey: .classSections) ?? [1, 2]
        teacher = try values.decodeIfPresent(String.self, forKey: .teacher)
        location = try values.decodeIfPresent(String.self, forKey: .location)
        guard (1...7).contains(dayOfWeek) else {
            throw OfflineDataError.invalidField("dayOfWeek")
        }
        guard !classSections.isEmpty, classSections.allSatisfy({ $0 > 0 }) else {
            throw OfflineDataError.invalidField("classSections")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case weekRange, repeatRule, dayOfWeek, classSections, teacher, location
    }
}

public struct OfflineSemester: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var startDate: String
    public var endDate: String
    public var weekCount: Int
    public var sectionCount: Int
    public var sectionTimes: [OfflineSectionTime]

    public init(
        id: String,
        name: String = "学期",
        startDate: String,
        endDate: String,
        weekCount: Int = 17,
        sectionCount: Int = 13,
        sectionTimes: [OfflineSectionTime] = []
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.weekCount = weekCount
        self.sectionCount = sectionCount
        self.sectionTimes = sectionTimes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "学期"
        startDate = try values.decodeIfPresent(String.self, forKey: .startDate) ?? "1970-01-01"
        endDate = try values.decodeIfPresent(String.self, forKey: .endDate) ?? "1970-01-01"
        weekCount = try values.decodeIfPresent(Int.self, forKey: .weekCount) ?? 17
        sectionCount = try values.decodeIfPresent(Int.self, forKey: .sectionCount) ?? 13
        sectionTimes = try values.decodeIfPresent([OfflineSectionTime].self, forKey: .sectionTimes) ?? []
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineDataError.invalidField("semester.id")
        }
        try Self.validateDate(startDate)
        try Self.validateDate(endDate)
        guard weekCount > 0, sectionCount > 0 else {
            throw OfflineDataError.invalidField("semester counts")
        }
    }

    public static func validateDate(_ value: String) throws {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              ISO8601DateFormatter.calendarDate(from: value) != nil else {
            throw OfflineDataError.invalidDate(value)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, startDate, endDate, weekCount, sectionCount, sectionTimes
    }
}

private extension ISO8601DateFormatter {
    static func calendarDate(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

public struct OfflineCourse: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var semesterId: String
    public var timeSlots: [OfflineTimeSlot]
    public var code: String?
    public var location: String?
    public var credits: Double?
    public var teacher: String?
    public var assessmentMethod: OfflineAssessmentMethod?
    public var notes: String?
    public var color: String?

    public init(
        id: String,
        name: String,
        semesterId: String,
        timeSlots: [OfflineTimeSlot] = [],
        code: String? = nil,
        location: String? = nil,
        credits: Double? = nil,
        teacher: String? = nil,
        assessmentMethod: OfflineAssessmentMethod? = nil,
        notes: String? = nil,
        color: String? = nil
    ) {
        self.id = id
        self.name = name
        self.semesterId = semesterId
        self.timeSlots = timeSlots
        self.code = code
        self.location = location
        self.credits = credits
        self.teacher = teacher
        self.assessmentMethod = assessmentMethod
        self.notes = notes
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "课程"
        semesterId = try values.decode(String.self, forKey: .semesterId)
        timeSlots = try values.decodeIfPresent([OfflineTimeSlot].self, forKey: .timeSlots) ?? []
        code = try values.decodeIfPresent(String.self, forKey: .code)
        location = try values.decodeIfPresent(String.self, forKey: .location)
        credits = try values.decodeIfPresent(Double.self, forKey: .credits)
        teacher = try values.decodeIfPresent(String.self, forKey: .teacher)
        let assessmentValue = try values.decodeIfPresent(String.self, forKey: .assessmentMethod)
        if let assessmentValue {
            assessmentMethod = try OfflineAssessmentMethod(wireValue: assessmentValue)
        } else {
            assessmentMethod = nil
        }
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        color = try values.decodeIfPresent(String.self, forKey: .color)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !semesterId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineDataError.invalidField("course identifier")
        }
        if let credits, credits < 0 || !credits.isFinite {
            throw OfflineDataError.invalidField("course.credits")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, semesterId, timeSlots, code, location, credits, teacher
        case assessmentMethod, notes, color
    }
}

public struct OfflineGrade: Codable, Equatable, Identifiable {
    public var id: String
    public var course: String
    public var credits: Double
    public var point: Double?
    public var score: Double?
    public var category: String
    public var detail: String

    public init(
        id: String = UUID().uuidString,
        course: String,
        credits: Double = 0,
        point: Double? = nil,
        score: Double? = nil,
        category: String = "课程",
        detail: String = ""
    ) {
        self.id = id
        self.course = course
        self.credits = credits
        self.point = point
        self.score = score
        self.category = category
        self.detail = detail
    }
}

public struct OfflineDisplaySettings: Codable, Equatable {
    public var themeColor: String
    public var darkMode: Bool

    public init(themeColor: String = "#2F80ED", darkMode: Bool = false) {
        self.themeColor = themeColor
        self.darkMode = darkMode
    }
}

/// Private app state. `grades` are intentionally local-only and are never emitted by
/// `AndroidBackupImporter` or `PortableBackupExporter`.
public struct OfflineAppState: Codable, Equatable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var courses: [OfflineCourse]
    public var semesters: [OfflineSemester]
    public var selectedSemesterId: String
    public var display: OfflineDisplaySettings
    public var grades: [OfflineGrade]
    /// Latest GPA selected by the portal contract. This is private app state
    /// and is deliberately excluded from the portable Android backup.
    public var gpa: Double?
    /// Latest locally collected electricity value. It is private app state and
    /// deliberately excluded from the portable Android backup envelope.
    public var electricityBalance: Double?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, courses, semesters, selectedSemesterId, display, grades, gpa, electricityBalance
    }

    public init(
        schemaVersion: Int = currentSchemaVersion,
        courses: [OfflineCourse] = [],
        semesters: [OfflineSemester] = [],
        selectedSemesterId: String = "",
        display: OfflineDisplaySettings = OfflineDisplaySettings(),
        grades: [OfflineGrade] = [],
        gpa: Double? = nil,
        electricityBalance: Double? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.courses = courses
        self.semesters = semesters
        self.selectedSemesterId = selectedSemesterId
        self.display = display
        self.grades = grades
        self.gpa = gpa
        self.electricityBalance = electricityBalance
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        courses = try values.decodeIfPresent([OfflineCourse].self, forKey: .courses) ?? []
        semesters = try values.decodeIfPresent([OfflineSemester].self, forKey: .semesters) ?? []
        selectedSemesterId = try values.decodeIfPresent(String.self, forKey: .selectedSemesterId) ?? ""
        display = try values.decodeIfPresent(OfflineDisplaySettings.self, forKey: .display) ?? OfflineDisplaySettings()
        grades = try values.decodeIfPresent([OfflineGrade].self, forKey: .grades) ?? []
        gpa = try values.decodeIfPresent(Double.self, forKey: .gpa)
        electricityBalance = try values.decodeIfPresent(Double.self, forKey: .electricityBalance)
    }

    public func validated() throws -> OfflineAppState {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw OfflineDataError.unsupportedSchemaVersion(schemaVersion)
        }
        var semesterIDs = Set<String>()
        for semester in semesters {
            guard semesterIDs.insert(semester.id).inserted else {
                throw OfflineDataError.duplicateID(semester.id)
            }
        }
        var courseIDs = Set<String>()
        for course in courses {
            guard courseIDs.insert(course.id).inserted else {
                throw OfflineDataError.duplicateID(course.id)
            }
            guard semesterIDs.contains(course.semesterId) else {
                throw OfflineDataError.danglingReference(course.semesterId)
            }
            if let credits = course.credits, credits < 0 || !credits.isFinite {
                throw OfflineDataError.invalidField("course.credits")
            }
            for slot in course.timeSlots {
                guard (1...7).contains(slot.dayOfWeek), !slot.classSections.isEmpty,
                      slot.classSections.allSatisfy({ $0 > 0 }) else {
                    throw OfflineDataError.invalidField("course.timeSlots")
                }
            }
        }
        if !selectedSemesterId.isEmpty && !semesterIDs.contains(selectedSemesterId) {
            throw OfflineDataError.danglingReference(selectedSemesterId)
        }
        var gradeIDs = Set<String>()
        for grade in grades {
            guard !grade.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OfflineDataError.invalidField("grade.id")
            }
            guard gradeIDs.insert(grade.id).inserted else {
                throw OfflineDataError.duplicateID(grade.id)
            }
            guard !grade.course.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OfflineDataError.invalidField("grade.course")
            }
            guard grade.credits.isFinite, grade.credits >= 0 else {
                throw OfflineDataError.invalidField("grade.credits")
            }
            if let point = grade.point, !point.isFinite || point < 0 || point > 5 {
                throw OfflineDataError.invalidField("grade.point")
            }
            if let score = grade.score, !score.isFinite || score < 0 || score > 100 {
                throw OfflineDataError.invalidField("grade.score")
            }
        }
        if let electricityBalance,
           !electricityBalance.isFinite || electricityBalance < 0 || electricityBalance >= 100000 {
            throw OfflineDataError.invalidField("electricityBalance")
        }
        if let gpa, !gpa.isFinite || !(0.0...5.0).contains(gpa) {
            throw OfflineDataError.invalidField("gpa")
        }
        return self
    }
}
