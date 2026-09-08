import Foundation

/// Pure Foundation parsers for the portal collection contract.
///
/// This type deliberately accepts only response bytes/text and returns the
/// same offline domain values used by the local app. It does not own cookies,
/// credentials, WebKit, or transport policy.
public enum PortalCollectionParsers {
    public struct GradeAPIResult: Equatable {
        public let grades: [OfflineGrade]
        public let apiGPA: Double?

        public init(grades: [OfflineGrade], apiGPA: Double?) {
            self.grades = grades
            self.apiGPA = apiGPA
        }
    }

    public struct SchedulePayload: Equatable {
        public let semesters: [OfflineSemester]
        public let courses: [OfflineCourse]

        public init(semesters: [OfflineSemester], courses: [OfflineCourse]) {
            self.semesters = semesters
            self.courses = courses
        }
    }

    /// The dated semester metadata used by the Android foreground collector
    /// to choose the current or next course-table request. Keep this value
    /// type free of response dictionaries so the selection policy stays
    /// deterministic and easy to test on every platform.
    public struct ScheduleSemesterCandidate: Equatable {
        public let id: String
        public let name: String
        public let startDate: String
        public let endDate: String?

        public init(id: String, name: String = "", startDate: String, endDate: String? = nil) {
            self.id = id
            self.name = name
            self.startDate = startDate
            self.endDate = endDate
        }
    }

    public struct ScheduleSemesterSelection: Equatable {
        public let ordered: [ScheduleSemesterCandidate]
        public let initialIndex: Int

        public init(ordered: [ScheduleSemesterCandidate], initialIndex: Int) {
            self.ordered = ordered
            self.initialIndex = initialIndex
        }

        public var initial: ScheduleSemesterCandidate { ordered[initialIndex] }
    }

    private static let dayNames: [String: Int] = [
        "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
        "六": 6, "日": 7, "天": 7,
        "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
    ]

    // MARK: Grades

    /// Extracts the opaque student identifier from the page bootstrap HTML.
    /// The value is used only in-memory to construct allow-listed requests.
    public static func discoverStudentID(from html: String) -> String? {
        let patterns = [
            #"(?i)id\s*=\s*[\"']studentId[\"'][^>]*value\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?i)value\s*=\s*[\"']([^\"']+)[\"'][^>]*id\s*=\s*[\"']studentId[\"']"#,
            #"(?i)(?:studentId|studentAssoc)\s*[=:]\s*[\"']([^\"']+)[\"']"#,
        ]
        for pattern in patterns {
            if let value = firstRegexMatch(pattern, in: html), !value.isEmpty { return value }
        }
        return nil
    }

    /// Extracts semester identifiers from the server-rendered bootstrap data.
    /// It supports the JSON.parse string used by the Android WebView flow and
    /// a direct JSON array assignment used by older portal pages.
    public static func discoverSemesterIDs(from html: String) -> [String] {
        embeddedSemesterObjects(from: html).compactMap { firstNonEmpty(string($0["id"]), string($0["code"])) }
    }

    /// Reads the same semester array that Android's `api_collect.js` uses.
    /// Invalid or undated entries are retained here so callers can report an
    /// unavailable dated semester instead of silently choosing the wrong one.
    public static func discoverScheduleSemesters(from html: String) -> [ScheduleSemesterCandidate] {
        embeddedSemesterObjects(from: html).compactMap(scheduleSemesterCandidate)
    }

    /// Reproduces Android's `chooseInitialSemester` policy: dated semesters
    /// are sorted by start date, the containing semester wins, otherwise the
    /// next future semester is selected, and after all dates the latest one is
    /// retained. A missing end date leaves a semester open-ended, as on
    /// Android.
    public static func selectScheduleSemester(
        from candidates: [ScheduleSemesterCandidate],
        today: String
    ) -> ScheduleSemesterSelection? {
        guard validDate(today) else { return nil }
        let sorted = candidates
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validDate($0.startDate) }
            .sorted { left, right in
                if left.startDate != right.startDate { return left.startDate < right.startDate }
                return left.id < right.id
            }
        guard !sorted.isEmpty else { return nil }

        if let containing = sorted.firstIndex(where: { candidate in
            let endDate = candidate.endDate.flatMap { validDate($0) ? $0 : nil }
            return candidate.startDate <= today && (endDate == nil || endDate! >= today)
        }) {
            return ScheduleSemesterSelection(ordered: sorted, initialIndex: containing)
        }
        let next = sorted.firstIndex { $0.startDate > today } ?? (sorted.count - 1)
        return ScheduleSemesterSelection(ordered: sorted, initialIndex: next)
    }

    /// Calculates the effective last activity date used to decide whether a
    /// selected semester has already ended. Empty schedules still cover two
    /// weeks, matching Android's `lastActivityDate` fallback.
    public static func effectiveScheduleEndDate(startDate: String, printData: Data) -> String? {
        guard let root = try? jsonObject(printData) else { return nil }
        let table = root["studentTableVm"] as? [String: Any]
        let activities = table?["activities"] as? [Any] ?? []
        return effectiveEndDate(startDate, activities: activities)
    }

    public static func parseGradeAPI(_ data: Data) throws -> GradeAPIResult {
        let root = try jsonObject(data)
        let responses = root["gradeResponses"] as? [Any] ?? []
        let grades = parseGradeObjects(from: responses)
        let gpa = root["gpaResponse"].flatMap(parseGPA)
        return GradeAPIResult(grades: grades, apiGPA: gpa)
    }

    public static func parseGradeAPIRecords(_ data: Data) throws -> [OfflineGrade] {
        let root = try jsonObject(data)
        if let records = root["records"] as? [Any] {
            return records.enumerated().compactMap { index, raw in
                guard let object = raw as? [String: Any] else { return nil }
                return gradeRecord(object, index: index)
            }
        }
        if let responses = root["gradeResponses"] as? [Any] {
            return parseGradeObjects(from: responses)
        }
        return []
    }

    /// Parses the small, sanitized payload returned by the visible education
    /// WebView collector. The page script never sends cookies, credentials,
    /// student identifiers or raw HTML; it sends the same domain fields that
    /// the offline contract already validates.
    public static func parseVisibleEducation(_ data: Data) throws -> PortalVisibleEducationData {
        let root = try jsonObject(data)
        let gradeData = try JSONSerialization.data(withJSONObject: [
            "records": root["grades"] as? [Any] ?? [],
        ], options: [])
        var grades = try parseGradeAPIRecords(gradeData)
        if grades.isEmpty, let responses = root["gradeResponses"] {
            let responseData = try JSONSerialization.data(withJSONObject: ["gradeResponses": responses])
            grades = try parseGradeAPIRecords(responseData)
        }

        let scheduleRoot = root["schedule"] as? [String: Any] ?? [:]
        let semester = scheduleRoot["semester"] as? [String: Any] ?? [
            "id": "current",
            "name": "当前学期",
            "startDate": "1970-01-01",
            "endDate": "1970-01-01",
        ]
        let activities = (scheduleRoot["activities"] as? [[String: Any]] ?? []).map { activity in
            var normalized: [String: Any] = [
                "courseName": activity["name"] ?? activity["courseName"] ?? "",
                "courseCode": activity["code"] ?? activity["courseCode"] ?? "",
                "credits": activity["credits"] ?? 0,
                "weekday": activity["weekday"] ?? 0,
                "startUnit": activity["startUnit"] ?? 0,
                "endUnit": activity["endUnit"] ?? 0,
                "weekIndexes": activity["weekIndexes"] ?? [],
                "teachers": activity["teachers"] ?? [],
                "campus": activity["campus"] ?? "",
                "building": activity["building"] ?? "",
                "room": activity["room"] ?? "",
            ]
            if let location = activity["location"] { normalized["location"] = location }
            return normalized
        }
        let printData: [String: Any] = [
            "studentTableVm": ["activities": activities],
        ]
        let scheduleData = try JSONSerialization.data(withJSONObject: [
            "semester": semester,
            "printData": printData,
        ], options: [])
        let schedule = try parseSchedulePayload(scheduleData)
        let gpa = root["gpa"].flatMap(parseGPA)
        return PortalVisibleEducationData(
            grades: keepHighest(grades),
            gpa: gpa,
            schedule: schedule
        )
    }

    public static func parsePortraitGPA(_ html: String) -> Double? {
        let text = decodeEntities(stripHTML(html))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)(?:(?:累计|总)?平均(?:学分)?绩点|GPA)\s*[：:]?\s*(\d(?:\.\d{1,4})?)"#,
            #"(?i)(\d(?:\.\d{1,4})?)\s*个人\s*GPA"#,
        ]
        for pattern in patterns {
            guard let match = firstRegexMatch(pattern, in: text),
                  let value = Double(match) else { continue }
            if isValidGPA(value) { return value }
        }
        return nil
    }

    public static func selectGPA(api: Double?, portrait: Double?) -> Double? {
        if let api, isValidGPA(api) { return api }
        if let portrait, isValidGPA(portrait) { return portrait }
        return nil
    }

    public static func keepHighest(_ grades: [OfflineGrade]) -> [OfflineGrade] {
        var result: [OfflineGrade] = []
        var indexByName: [String: Int] = [:]
        for grade in grades {
            let key = normalizedCourseName(grade.course)
            guard !key.isEmpty else { continue }
            guard let index = indexByName[key] else {
                indexByName[key] = result.count
                result.append(grade)
                continue
            }
            if isHigher(grade, than: result[index]) { result[index] = grade }
        }
        return result
    }

    // MARK: Schedule

    public static func parseScheduleText(_ text: String) -> [OfflineTimeSlot] {
        let normalized = text
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "～", with: "~")
            .replacingOccurrences(of: "－", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let day = firstRegexMatch(#"(?:星期|周)\s*([一二三四五六日天1-7])"#, in: normalized)
            .flatMap { dayNames[$0] } ?? 0
        guard (1...7).contains(day) else { return [] }
        let sectionValues = regexCaptureGroups(#"(\d+)\s*(?:-|~|至)\s*(\d+)\s*节"#, in: normalized)
        let sectionStart: Int
        let sectionEnd: Int
        if let groups = sectionValues.first, groups.count == 2,
           let start = Int(groups[0]), let end = Int(groups[1]) {
            sectionStart = start
            sectionEnd = end
        } else if let single = firstRegexMatch(#"(\d+)\s*节"#, in: normalized), let value = Int(single) {
            sectionStart = value
            sectionEnd = value
        } else {
            return []
        }
        guard sectionStart > 0, sectionEnd >= sectionStart else { return [] }
        let sections = Array(sectionStart...sectionEnd)

        // The first 周 before the day label terminates the week expression.
        guard let weekEnd = normalized.range(of: "周") else { return [] }
        let weekExpression = String(normalized[..<weekEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = weekExpression
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",", omittingEmptySubsequences: true)
            .map(String.init)
        guard !tokens.isEmpty else { return [] }

        return tokens.compactMap { token in
            let repeatRule: OfflineRepeatRule = token.contains("双") ? .even
                : (token.contains("单") ? .odd : .all)
            let numbers = regexCaptureGroups(#"(\d+)\s*(?:~|-|至)\s*(\d+)"#, in: token)
            let range: String
            if let groups = numbers.first, groups.count == 2,
               let start = Int(groups[0]), let end = Int(groups[1]), start > 0, end >= start {
                range = "\(start)-\(end)"
            } else if let single = firstRegexMatch(#"\d+"#, in: token), Int(single) ?? 0 > 0 {
                range = single
            } else {
                return nil
            }
            return OfflineTimeSlot(
                weekRange: range,
                repeatRule: repeatRule,
                dayOfWeek: day,
                classSections: sections
            )
        }
    }

    public static func parseSchedulePayload(_ data: Data) throws -> SchedulePayload {
        let root = try jsonObject(data)
        if let semester = root["semester"] as? [String: Any] {
            return parseActivityPayload(semester: semester, printData: root["printData"] as? [String: Any])
        }
        return parseCoursePayload(root)
    }

    // MARK: Electricity

    public static func parseElectricityBalance(_ data: Data) -> Double? {
        guard let root = try? jsonObject(data) else { return nil }
        // The API collector wraps the actual response in `response` while
        // fixture/test callers may pass that response directly.
        let candidate: [String: Any]
        if let response = root["response"] as? [String: Any] {
            candidate = response
        } else if root["map"] != nil {
            candidate = root
        } else if let valid = root["valid"] as? [String: Any] {
            // The shared anomaly fixture groups sample responses under
            // `valid`/`negative`/`malformed`; production responses use the
            // direct shape or the `response` wrapper.
            candidate = valid
        } else {
            return nil
        }
        guard let map = candidate["map"] as? [String: Any],
              let showData = map["showData"] as? [String: Any] else { return nil }
        for key in ["当前剩余电量", "剩余电量", "电费余额", "剩余电费"] {
            guard let raw = showData[key] else { continue }
            let text = String(describing: raw)
            guard let token = firstRegexMatch(#"[-+]?\d+(?:\.\d+)?"#, in: text),
                  let value = Double(token) else { continue }
            if value.isFinite, value >= 0, value < 100000 { return value }
        }
        return nil
    }

    // MARK: Internal JSON mapping

    private static func parseGradeObjects(from responses: [Any]) -> [OfflineGrade] {
        var output: [OfflineGrade] = []
        for response in responses {
            guard let object = response as? [String: Any],
                  let semesterMap = object["semesterId2studentGrades"] as? [String: Any] else { continue }
            for semester in semesterMap.keys.sorted() {
                guard let rows = semesterMap[semester] as? [Any] else { continue }
                for raw in rows {
                    guard let grade = raw as? [String: Any] else { continue }
                    if let published = grade["published"] as? Bool, !published { continue }
                    let courseObject = grade["course"] as? [String: Any]
                    let name = firstNonEmpty(
                        courseObject?["nameZh"] as? String,
                        grade["lessonNameZh"] as? String
                    )
                    guard !name.isEmpty else { continue }
                    let index = output.count
                    output.append(OfflineGrade(
                        id: "grade-\(stableToken(semester))-\(index)",
                        course: name,
                        credits: number(courseObject?["credits"]) ?? 0,
                        point: number(grade["gp"]),
                        score: number(grade["gaGrade"]),
                        category: grade["category"] as? String ?? "课程",
                        detail: normalizeDetail(grade["gradeDetail"] as? String ?? "")
                    ))
                }
            }
        }
        return output
    }

    private static func gradeRecord(_ object: [String: Any], index: Int) -> OfflineGrade? {
        guard let course = object["course"] as? String,
              !course.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return OfflineGrade(
            id: object["id"] as? String ?? "grade-record-\(index)",
            course: course,
            credits: number(object["credits"]) ?? 0,
            point: number(object["point"]),
            score: number(object["score"]),
            category: object["category"] as? String ?? "课程",
            detail: normalizeDetail(object["detail"] as? String ?? "")
        )
    }

    private static func parseActivityPayload(semester: [String: Any], printData: [String: Any]?) -> SchedulePayload {
        let table = printData?["studentTableVm"] as? [String: Any]
        let activities = table?["activities"] as? [Any] ?? []
        let semesterID = firstNonEmpty(string(semester["id"]), string(semester["code"]), "current")
        let semesterName = firstNonEmpty(string(semester["nameZh"]), string(semester["name"]), string(semester["code"]), "当前学期")
        let startDate = string(semester["startDate"])
        let explicitEnd = string(semester["endDate"])
        var grouped: [String: OfflineCourse] = [:]
        var order: [String] = []
        for raw in activities {
            guard let activity = raw as? [String: Any] else { continue }
            guard let name = activity["courseName"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let weekday = int(activity["weekday"])
            let start = int(activity["startUnit"])
            let end = int(activity["endUnit"])
            guard (1...7).contains(weekday), start > 0, end >= start else { continue }
            let location = joinUnique(string(activity["campus"]), string(activity["building"]), string(activity["room"]))
            guard !containsOnline(name), !containsOnline(location) else { continue }
            let code = string(activity["courseCode"])
            let key = "\(semesterID)|\(code.isEmpty ? name : code)"
            let teachers = normalizedTeachers(activity["teachers"])
            let weeks = activity["weekIndexes"] as? [Any] ?? []
            let slots = slotsFromWeekIndexes(weeks, weekday: weekday, start: start, end: end, teacher: teachers, location: location)
            var course = grouped[key] ?? OfflineCourse(
                id: "course-\(stableToken(key))",
                name: name,
                semesterId: semesterID,
                timeSlots: [],
                code: code.isEmpty ? nil : code,
                location: nil,
                credits: number(activity["credits"]),
                teacher: nil
            )
            course.timeSlots.append(contentsOf: slots)
            course.teacher = joinNames((course.teacher ?? "").split(separator: "、").map(String.init) + (teachers ?? "").split(separator: "、").map(String.init))
            course.location = joinLines((course.location ?? "").split(separator: "\n").map(String.init) + (location.isEmpty ? [] : [location]))
            if course.credits == nil { course.credits = number(activity["credits"]) }
            if grouped[key] == nil { order.append(key) }
            grouped[key] = course
        }
        // Explicit portal dates are authoritative. Derive a date only when
        // the response omitted it (including the empty-course case).
        let finalEnd = validDate(explicitEnd)
            ? explicitEnd
            : (effectiveEndDate(startDate, activities: activities) ?? explicitEnd)
        let offlineSemester = OfflineSemester(
            id: semesterID,
            name: semesterName,
            startDate: validDate(startDate) ? startDate : "1970-01-01",
            endDate: validDate(finalEnd) ? finalEnd : (validDate(startDate) ? startDate : "1970-01-01")
        )
        return SchedulePayload(semesters: [offlineSemester], courses: order.compactMap { grouped[$0] })
    }

    private static func parseCoursePayload(_ root: [String: Any]) -> SchedulePayload {
        let semesterID = firstNonEmpty(string(root["targetDataSemester"]), string(root["semesterId"]), "current")
        var grouped: [String: OfflineCourse] = [:]
        var order: [String] = []
        for raw in root["courses"] as? [Any] ?? [] {
            guard let item = raw as? [String: Any], let name = item["name"] as? String, !name.isEmpty else { continue }
            let location = string(item["location"])
            guard !containsOnline(name), !containsOnline(location) else { continue }
            let code = string(item["code"])
            let key = "\(semesterID)|\(code.isEmpty ? name : code)"
            let slots = parseScheduleText(item["scheduleText"] as? String ?? "").map {
                OfflineTimeSlot(weekRange: $0.weekRange, repeatRule: $0.repeatRule, dayOfWeek: $0.dayOfWeek, classSections: $0.classSections, teacher: normalizedTeachers(item["teacher"]), location: location.isEmpty ? nil : location)
            }
            var course = grouped[key] ?? OfflineCourse(id: "course-\(stableToken(key))", name: name, semesterId: semesterID, code: code.isEmpty ? nil : code)
            course.timeSlots.append(contentsOf: slots)
            course.teacher = joinNames((course.teacher ?? "").split(separator: "、").map(String.init) + (normalizedTeachers(item["teacher"]) ?? "").split(separator: "、").map(String.init))
            course.location = joinLines((course.location ?? "").split(separator: "\n").map(String.init) + (location.isEmpty ? [] : [location]))
            if course.credits == nil { course.credits = number(item["credits"]) }
            if grouped[key] == nil { order.append(key) }
            grouped[key] = course
        }
        let semester = OfflineSemester(id: semesterID, name: "当前学期", startDate: "1970-01-01", endDate: "1970-01-01")
        return SchedulePayload(semesters: [semester], courses: order.compactMap { grouped[$0] })
    }

    private static func slotsFromWeekIndexes(_ values: [Any], weekday: Int, start: Int, end: Int, teacher: String?, location: String) -> [OfflineTimeSlot] {
        let weeks = Array(Set(values.compactMap { int($0) }.filter { $0 > 0 })).sorted()
        guard !weeks.isEmpty else { return [OfflineTimeSlot(weekRange: "1-17", dayOfWeek: weekday, classSections: Array(start...end), teacher: teacher, location: location.isEmpty ? nil : location)] }
        var slots: [OfflineTimeSlot] = []
        var index = 0
        while index < weeks.count {
            let first = weeks[index]
            var last = first
            while index + 1 < weeks.count, weeks[index + 1] == last + 1 { index += 1; last = weeks[index] }
            slots.append(OfflineTimeSlot(weekRange: first == last ? "\(first)" : "\(first)-\(last)", dayOfWeek: weekday, classSections: Array(start...end), teacher: teacher, location: location.isEmpty ? nil : location))
            index += 1
        }
        return slots
    }

    private static func effectiveEndDate(_ start: String, activities: [Any]) -> String? {
        guard let date = parseDate(start) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: date)
        let mondayOffset = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: date) else { return nil }
        var last = calendar.date(byAdding: .day, value: 13, to: monday) ?? monday
        for raw in activities {
            guard let item = raw as? [String: Any], let weeks = item["weekIndexes"] as? [Any] else { continue }
            let day = int(item["weekday"])
            guard (1...7).contains(day) else { continue }
            for week in weeks.compactMap({ int($0) }).filter({ $0 > 0 }) {
                if let occurrence = calendar.date(byAdding: .day, value: (week - 1) * 7 + day - 1, to: monday), occurrence > last { last = occurrence }
            }
        }
        return formatDate(last)
    }

    // MARK: Helpers

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty else { throw OfflineDataError.emptyBackup }
        guard let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw OfflineDataError.malformedBackup("portal response root must be an object")
        }
        return object
    }

    private static func embeddedSemesterObjects(from html: String) -> [[String: Any]] {
        let parsePattern = #"(?s)(?:var|let|const)\s+semesters\s*=\s*JSON\.parse\(\s*['\"](.*?)['\"]\s*\)"#
        if let encoded = firstRegexMatch(parsePattern, in: html),
           let decoded = decodeJavascriptString(encoded),
           let data = decoded.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array
        }
        let directPattern = #"(?s)(?:var|let|const)\s+semesters\s*=\s*(\[[\s\S]*?\])\s*;"#
        if let raw = firstRegexMatch(directPattern, in: html),
           let data = raw.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array
        }
        return []
    }

    private static func scheduleSemesterCandidate(_ object: [String: Any]) -> ScheduleSemesterCandidate? {
        let id = firstNonEmpty(string(object["id"]), string(object["code"]), string(object["dataSemester"]))
        guard !id.isEmpty else { return nil }
        let name = firstNonEmpty(string(object["nameZh"]), string(object["name"]), string(object["title"]), id)
        let startDate = string(object["startDate"])
        let endDate = string(object["endDate"])
        return ScheduleSemesterCandidate(
            id: id,
            name: name,
            startDate: startDate,
            endDate: endDate.isEmpty ? nil : endDate
        )
    }

    private static func decodeJavascriptString(_ value: String) -> String? {
        var normalized = value.replacingOccurrences(of: "\\'", with: "'")
        normalized = normalized.replacingOccurrences(of: "\\/", with: "/")
        normalized = normalized.replacingOccurrences(of: "\\\\", with: "\\")
        if let data = ("\"" + normalized.replacingOccurrences(of: "\"", with: "\\\"") + "\"").data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? String {
            return decoded
        }
        return normalized
    }

    private static func parseGPA(_ value: Any?) -> Double? {
        guard let object = value as? [String: Any] else { return value.flatMap { number($0) } .flatMap { isValidGPA($0) ? $0 : nil } }
        if let direct = object.first(where: { isGPAKey($0.key) }).flatMap({ number($0.value) }), isValidGPA(direct) { return direct }
        for child in object.values {
            if let found = parseGPA(child) { return found }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        guard let value else { return nil }
        let text = String(describing: value)
        guard let match = firstRegexMatch(#"[-+]?\d+(?:\.\d+)?"#, in: text) else { return nil }
        return Double(match)
    }

    private static func isValidGPA(_ value: Double) -> Bool { value.isFinite && (0...5).contains(value) }
    private static func isGPAKey(_ key: String) -> Bool {
        let normalized = key.replacingOccurrences(of: #"[\s_-]"#, with: "", options: .regularExpression).lowercased()
        return ["gpa", "avggpa", "averagegpa", "studentgpa", "cumulativegpa", "gradepointaverage", "averagegradepoint", "平均绩点", "平均学分绩点", "累计平均学分绩点"].contains(normalized)
    }

    private static func isHigher(_ candidate: OfflineGrade, than current: OfflineGrade) -> Bool {
        if let left = candidate.score, let right = current.score, left != right { return left > right }
        if candidate.score != nil, current.score == nil { return true }
        if let left = candidate.point, let right = current.point, left != right { return left > right }
        return candidate.point != nil && current.point == nil
    }

    private static func normalizedCourseName(_ value: String) -> String { value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased() }
    private static func normalizeDetail(_ value: String) -> String { stripHTML(decodeEntities(value)).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func stripHTML(_ value: String) -> String { value.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: " ", options: .regularExpression).replacingOccurrences(of: #"(?s)<[^>]*>"#, with: " ", options: .regularExpression) }
    private static func decodeEntities(_ value: String) -> String { value.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&#x27;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&") }
    private static func firstNonEmpty(_ values: String?...) -> String { for value in values { if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value.trimmingCharacters(in: .whitespacesAndNewlines) } }; return "" }
    private static func string(_ value: Any?) -> String { guard let value else { return "" }; if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }; return String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func int(_ value: Any?) -> Int { if let n = value as? NSNumber { return n.intValue }; return Int(string(value)) ?? 0 }
    private static func normalizedTeachers(_ value: Any?) -> String? {
        guard let value else { return nil }

        // JSONSerialization may bridge a JSON string array as either [String]
        // or [Any] depending on the platform. Handle both before falling back
        // to scalar text so an array is never persisted as `['["..."]']`.
        let rawValues: [String]
        if let array = value as? [String] {
            rawValues = array
        } else if let array = value as? [Any] {
            rawValues = array.compactMap { normalizedTeachers($0) }
        } else if let array = value as? NSArray {
            rawValues = array.compactMap { normalizedTeachers($0) }
        } else {
            rawValues = [string(value)]
        }

        let values = rawValues.flatMap {
            $0.split(whereSeparator: { $0 == "、" || $0 == "/" || $0 == "," || $0 == "，" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let result = joinNames(values)
        return result.isEmpty ? nil : result
    }
    private static func joinNames(_ values: [String]) -> String { var seen = Set<String>(); return values.flatMap { $0.split(whereSeparator: { $0 == "、" || $0 == "/" || $0 == "," || $0 == "，" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: "、") }
    private static func joinLines(_ values: [String]) -> String { var seen = Set<String>(); return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: "\n") }
    private static func joinUnique(_ values: String?...) -> String { var seen = Set<String>(); return values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: " ") }
    private static func containsOnline(_ value: String) -> Bool { let lower = value.lowercased(); return lower.contains("网课") || lower.contains("线上") || lower.contains("在线") || lower.contains("online") }
    private static func validDate(_ value: String) -> Bool { parseDate(value) != nil }
    private static func parseDate(_ value: String) -> Date? { let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false; return formatter.date(from: value) }
    private static func formatDate(_ value: Date) -> String { let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: value) }
    private static func stableToken(_ value: String) -> String { var hash: UInt64 = 14695981039346656037; for byte in value.utf8 { hash ^= UInt64(byte); hash = hash &* 1099511628211 }; return String(hash, radix: 16) }
    private static func firstRegexMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let captureIndex = match.numberOfRanges > 1 ? 1 : 0
        guard let range = Range(match.range(at: captureIndex), in: text) else { return nil }
        return String(text[range])
    }
    private static func regexCaptureGroups(_ pattern: String, in text: String) -> [[String]] { guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }; return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } } } }
}
