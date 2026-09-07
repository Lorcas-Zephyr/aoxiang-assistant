import Foundation

public struct AndroidBackupImporter {
    public static let format = "aoxiang-assistant.schedule-backup"
    public static let currentSchemaVersion = 1
    public static let legacyVersion = "2.0"

    public init() {}

    public func importData(_ data: Data) throws -> OfflineAppState {
        guard !data.isEmpty else { throw OfflineDataError.emptyBackup }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw OfflineDataError.malformedBackup(error.localizedDescription)
        }
        guard let object = raw as? [String: Any] else {
            throw OfflineDataError.malformedBackup("root must be an object")
        }
        try validateSecurity(object)
        let legacy = try validateEnvelope(object)
        if let exportDate = object["exportDate"] {
            guard let value = exportDate as? String else {
                throw OfflineDataError.invalidField("exportDate")
            }
            try OfflineSemester.validateDate(value)
        }
        try validateEnvelopeRecords(object, legacy: legacy)
        let decoder = JSONDecoder()
        do {
            let normalized = try normalizedDocument(from: object, legacy: legacy)
            let normalizedData = try JSONSerialization.data(withJSONObject: normalized)
            let document = try decoder.decode(DecodedBackup.self, from: normalizedData)
            let state = OfflineAppState(
                courses: document.courses,
                semesters: document.settings.semesters,
                selectedSemesterId: document.settings.selectedSemesterId,
                display: OfflineDisplaySettings(
                    themeColor: document.settings.themeColor,
                    darkMode: document.settings.darkMode
                )
            )
            return try state.validated()
        } catch let error as OfflineDataError {
            throw error
        } catch {
            throw OfflineDataError.malformedBackup(error.localizedDescription)
        }
    }

    private func validateEnvelope(_ object: [String: Any]) throws -> Bool {
        let allowed: Set<String> = ["format", "schemaVersion", "version", "exportDate", "courses", "settings"]
        for key in object.keys where !allowed.contains(key) {
            throw OfflineDataError.unknownField(key)
        }
        if object["schemaVersion"] != nil {
            guard let format = object["format"] as? String else {
                throw OfflineDataError.missingField("format")
            }
            guard format == Self.format else { throw OfflineDataError.unsupportedFormat(format) }
            guard let schema = object["schemaVersion"] as? NSNumber,
                  String(cString: schema.objCType) != "c",
                  schema.intValue == 1,
                  schema.doubleValue == 1 else {
                if let schema = object["schemaVersion"] as? NSNumber {
                    throw OfflineDataError.unsupportedSchemaVersion(schema.intValue)
                }
                throw OfflineDataError.invalidField("schemaVersion")
            }
            if let marker = object["version"] as? String, marker != Self.legacyVersion {
                throw OfflineDataError.unsupportedLegacyVersion(marker)
            }
            return false
        }
        if object["format"] != nil { throw OfflineDataError.invalidField("format requires schemaVersion") }
        guard let version = object["version"] as? String else {
            throw OfflineDataError.missingField("version")
        }
        guard version == Self.legacyVersion else {
            throw OfflineDataError.unsupportedLegacyVersion(version)
        }
        return true
    }

    private func validateEnvelopeRecords(_ object: [String: Any], legacy: Bool) throws {
        guard let courses = object["courses"] as? [[String: Any]] else {
            throw OfflineDataError.missingField("courses")
        }
        guard let settings = object["settings"] as? [String: Any] else {
            throw OfflineDataError.missingField("settings")
        }
        let settingsKeys: Set<String> = ["semesters", "themeColor", "darkMode", "selectedSemesterId"]
        for key in settings.keys where !settingsKeys.contains(key) {
            throw OfflineDataError.unknownField("settings.\(key)")
        }
        if !legacy && settings["semesters"] == nil {
            throw OfflineDataError.missingField("settings.semesters")
        }
        if let semesters = settings["semesters"], !(semesters is [[String: Any]]) {
            throw OfflineDataError.invalidField("settings.semesters")
        }
        let semesterIDs = try validateSemesters(settings["semesters"] as? [[String: Any]] ?? [])
        var courseIDs = Set<String>()
        for course in courses {
            let id = try requiredString(course, key: "id", path: "course")
            guard courseIDs.insert(id).inserted else { throw OfflineDataError.duplicateID(id) }
            let semesterID = try requiredString(course, key: "semesterId", path: "course")
            guard semesterIDs.contains(semesterID) else { throw OfflineDataError.danglingReference(semesterID) }
            try validateCourse(course)
        }
        if let selected = settings["selectedSemesterId"] as? String,
           !selected.isEmpty, !semesterIDs.contains(selected) {
            throw OfflineDataError.danglingReference(selected)
        } else if settings["selectedSemesterId"] != nil && !(settings["selectedSemesterId"] is String) {
            throw OfflineDataError.invalidField("settings.selectedSemesterId")
        }
        if let theme = settings["themeColor"], !(theme is String) { throw OfflineDataError.invalidField("settings.themeColor") }
        if let dark = settings["darkMode"], !(dark is Bool) { throw OfflineDataError.invalidField("settings.darkMode") }
    }

    private func validateSemesters(_ semesters: [[String: Any]]) throws -> Set<String> {
        var IDs = Set<String>()
        for semester in semesters {
            try rejectUnknownKeys(
                semester,
                allowed: ["id", "name", "startDate", "endDate", "weekCount", "sectionCount", "sectionTimes"],
                path: "semester"
            )
            let id = try requiredString(semester, key: "id", path: "semester")
            guard IDs.insert(id).inserted else { throw OfflineDataError.duplicateID(id) }
            for key in ["startDate", "endDate"] {
                if let value = semester[key] as? String { try OfflineSemester.validateDate(value) }
                else if semester[key] != nil { throw OfflineDataError.invalidField("semester.\(key)") }
            }
            for key in ["weekCount", "sectionCount"] {
                if let value = semester[key] as? NSNumber, value.intValue > 0 {} else if semester[key] != nil {
                    throw OfflineDataError.invalidField("semester.\(key)")
                }
            }
            if let times = semester["sectionTimes"] as? [[String: Any]] {
                for time in times {
                    try rejectUnknownKeys(time, allowed: ["start", "end"], path: "sectionTime")
                    guard let start = time["start"] as? String, let end = time["end"] as? String else {
                        throw OfflineDataError.invalidField("sectionTimes")
                    }
                    try OfflineSectionTime.validateTime(start)
                    try OfflineSectionTime.validateTime(end)
                }
            } else if semester["sectionTimes"] != nil { throw OfflineDataError.invalidField("semester.sectionTimes") }
        }
        return IDs
    }

    private func validateCourse(_ course: [String: Any]) throws {
        try rejectUnknownKeys(
            course,
            allowed: ["id", "name", "semesterId", "timeSlots", "code", "location", "credits", "teacher", "assessmentMethod", "notes", "color"],
            path: "course"
        )
        if let slots = course["timeSlots"] as? [[String: Any]] {
            for slot in slots {
                try rejectUnknownKeys(
                    slot,
                    allowed: ["weekRange", "repeatRule", "dayOfWeek", "classSections", "teacher", "location"],
                    path: "timeSlot"
                )
                if let repeatRule = slot["repeatRule"] as? String {
                    _ = try OfflineRepeatRule(wireValue: repeatRule)
                } else if slot["repeatRule"] != nil { throw OfflineDataError.invalidField("timeSlot.repeatRule") }
                if let day = slot["dayOfWeek"] as? NSNumber, !(1...7).contains(day.intValue) {
                    throw OfflineDataError.invalidField("timeSlot.dayOfWeek")
                }
                if let sections = slot["classSections"] as? [NSNumber], sections.isEmpty || sections.contains(where: { $0.intValue < 1 }) {
                    throw OfflineDataError.invalidField("timeSlot.classSections")
                }
            }
        } else if course["timeSlots"] != nil { throw OfflineDataError.invalidField("course.timeSlots") }
        if let assessment = course["assessmentMethod"] as? String {
            _ = try OfflineAssessmentMethod(wireValue: assessment)
        } else if course["assessmentMethod"] != nil && !(course["assessmentMethod"] is NSNull) {
            throw OfflineDataError.invalidField("course.assessmentMethod")
        }
        if let credits = course["credits"] as? NSNumber, credits.doubleValue < 0 || !credits.doubleValue.isFinite {
            throw OfflineDataError.invalidField("course.credits")
        }
    }

    private func rejectUnknownKeys(
        _ object: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        for key in object.keys where !allowed.contains(key) {
            let normalized = key.lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
            let sensitive = [
                "password", "passwd", "pwd", "credential", "token", "cookie", "session",
                "authorization", "auth", "secret", "account", "username", "studentid",
                "userid", "identity", "sms", "captcha", "verification", "login",
            ].contains { normalized.contains($0) }
            if sensitive { throw OfflineDataError.sensitiveField(key) }
            throw OfflineDataError.unknownField("\(path).\(key)")
        }
    }

    private func requiredString(_ object: [String: Any], key: String, path: String) throws -> String {
        guard let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineDataError.missingField("\(path).\(key)")
        }
        return value
    }

    private func normalizedDocument(from object: [String: Any], legacy: Bool) throws -> [String: Any] {
        var result = object
        if legacy {
            result["format"] = Self.format
            result["schemaVersion"] = Self.currentSchemaVersion
            if var settings = result["settings"] as? [String: Any], settings["semesters"] == nil {
                settings["semesters"] = [[String: Any]]()
                result["settings"] = settings
            }
        }
        return result
    }

    private func validateSecurity(_ value: Any) throws {
        let forbidden = ["password", "passwd", "pwd", "credential", "token", "cookie", "session", "authorization", "auth", "secret", "account", "username", "studentid", "userid", "identity", "sms", "captcha", "verification", "login"]
        if let object = value as? [String: Any] {
            for (key, child) in object {
                let normalized = key.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
                if forbidden.contains(where: { normalized.contains($0) }) { throw OfflineDataError.sensitiveField(key) }
                try validateSecurity(child)
            }
        } else if let array = value as? [Any] {
            for child in array { try validateSecurity(child) }
        }
    }

    private struct DecodedBackup: Decodable {
        let courses: [OfflineCourse]
        let settings: Settings

        struct Settings: Decodable {
            let semesters: [OfflineSemester]
            let themeColor: String
            let darkMode: Bool
            let selectedSemesterId: String

            enum CodingKeys: String, CodingKey { case semesters, themeColor, darkMode, selectedSemesterId }

            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                semesters = try values.decodeIfPresent([OfflineSemester].self, forKey: .semesters) ?? []
                themeColor = try values.decodeIfPresent(String.self, forKey: .themeColor) ?? "#2F80ED"
                darkMode = try values.decodeIfPresent(Bool.self, forKey: .darkMode) ?? false
                selectedSemesterId = try values.decodeIfPresent(String.self, forKey: .selectedSemesterId) ?? ""
            }
        }
    }
}

public struct AndroidBackupExporter {
    public init() {}

    public func exportData(from state: OfflineAppState, exportDate: Date = Date()) throws -> Data {
        let valid = try state.validated()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
        formatter.dateFormat = "yyyy-MM-dd"
        let document: [String: Any] = [
            "format": AndroidBackupImporter.format,
            "schemaVersion": OfflineAppState.currentSchemaVersion,
            "version": AndroidBackupImporter.legacyVersion,
            "exportDate": formatter.string(from: exportDate),
            "courses": try jsonArray(valid.courses),
            "settings": [
                "semesters": try jsonArray(valid.semesters),
                "themeColor": valid.display.themeColor,
                "darkMode": valid.display.darkMode,
                "selectedSemesterId": valid.selectedSemesterId,
            ],
        ]
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted])
    }

    private func jsonArray<T: Encodable>(_ values: [T]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(values)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw OfflineDataError.malformedBackup("cannot encode portable records")
        }
        return result
    }
}
