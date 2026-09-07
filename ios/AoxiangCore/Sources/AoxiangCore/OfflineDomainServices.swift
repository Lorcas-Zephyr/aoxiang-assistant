import Foundation

public enum OfflineGradeService {
    public static func keepHighest(_ grades: [OfflineGrade]) -> [OfflineGrade] {
        var result: [OfflineGrade] = []
        var indexByName: [String: Int] = [:]
        for grade in grades {
            let key = grade.course.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                .lowercased()
            guard !key.isEmpty else { continue }
            guard let index = indexByName[key] else {
                indexByName[key] = result.count
                result.append(grade)
                continue
            }
            let current = result[index]
            if isHigher(grade, than: current) { result[index] = grade }
        }
        return result
    }

    public static func selectedGPA(api: Double?, portrait: Double?) -> Double? {
        if let api, api.isFinite, api >= 0 { return api }
        if let portrait, portrait.isFinite, portrait >= 0 { return portrait }
        return nil
    }

    public static func weightedScore(_ grades: [OfflineGrade]) -> Double? {
        let scored = grades.filter { $0.score?.isFinite == true && $0.credits > 0 }
        let credits = scored.reduce(0) { $0 + $1.credits }
        guard credits > 0 else { return nil }
        return scored.reduce(0) { $0 + ($1.score ?? 0) * $1.credits } / credits
    }

    private static func isHigher(_ candidate: OfflineGrade, than current: OfflineGrade) -> Bool {
        switch (candidate.score, current.score) {
        case let (left?, right?) where left != right: return left > right
        case (_?, nil): return true
        default: break
        }
        switch (candidate.point, current.point) {
        case let (left?, right?): return left > right
        case (_?, nil): return true
        default: return false
        }
    }
}

public enum OfflineScheduleService {
    public enum CampusScheduleSeason: String, Codable, Equatable {
        case winter
        case summer
    }

    public static func courses(
        in state: OfflineAppState,
        semesterID: String? = nil,
        includeOnline: Bool = true
    ) -> [OfflineCourse] {
        let selected = semesterID ?? state.selectedSemesterId
        return state.courses.filter { course in
            guard selected.isEmpty || course.semesterId == selected else { return false }
            guard includeOnline else {
                let locations = [course.location] + course.timeSlots.map(\.location)
                return !locations.compactMap { $0?.lowercased() }.contains(where: {
                    $0.contains("线上") || $0.contains("online")
                })
            }
            return true
        }
    }

    public static func courses(
        on dayOfWeek: Int,
        in state: OfflineAppState,
        semesterID: String? = nil
    ) -> [OfflineCourse] {
        courses(in: state, semesterID: semesterID).filter { course in
            course.timeSlots.contains { $0.dayOfWeek == dayOfWeek }
        }
    }

    /// Returns courses that are active on a particular academic week and day.
    /// The week range grammar accepts the Android forms `1-3`, `1~3`, comma/
    /// Chinese-comma separated weeks, and combinations such as `1,4-6`.
    public static func courses(
        on dayOfWeek: Int,
        week: Int,
        in state: OfflineAppState,
        semesterID: String? = nil
    ) -> [OfflineCourse] {
        guard (1...7).contains(dayOfWeek), week > 0 else { return [] }
        return courses(in: state, semesterID: semesterID).filter { course in
            course.timeSlots.contains { slot in
                slot.dayOfWeek == dayOfWeek
                    && isWeekActive(week, weekRange: slot.weekRange, repeatRule: slot.repeatRule)
            }
        }
    }

    public static func isWeekActive(
        _ week: Int,
        weekRange: String,
        repeatRule: OfflineRepeatRule = .all
    ) -> Bool {
        guard week > 0 else { return false }
        let normalized = weekRange
            .replacingOccurrences(of: "～", with: "~")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: " ", with: "")
        let tokens = normalized.split(separator: ",", omittingEmptySubsequences: true)
        guard !tokens.isEmpty else { return false }
        let inRange = tokens.contains { token in
            let value = String(token)
            let bounds = value.split(whereSeparator: { $0 == "-" || $0 == "~" })
            if bounds.count == 1, let single = Int(String(bounds[0])) { return single == week }
            guard bounds.count == 2,
                  let start = Int(String(bounds[0])),
                  let end = Int(String(bounds[1])) else {
                return false
            }
            return (min(start, end)...max(start, end)).contains(week)
        }
        guard inRange else { return false }
        switch repeatRule {
        case .all: return true
        case .odd: return week % 2 == 1
        case .even: return week % 2 == 0
        }
    }

    public static func sectionTime(
        _ section: Int,
        semester: OfflineSemester,
        location: String? = nil,
        season: CampusScheduleSeason? = nil
    ) -> OfflineSectionTime? {
        guard section > 0 else { return nil }
        if location?.contains("友谊") == true {
            let winter = [
                ("08:00", "08:50"), ("09:00", "09:50"), ("10:10", "11:00"),
                ("11:10", "12:00"), ("12:20", "13:05"), ("13:05", "13:50"),
                ("14:00", "14:50"), ("15:00", "15:50"), ("16:10", "17:00"),
                ("17:10", "18:00"), ("19:00", "19:50"), ("20:00", "20:50"),
                ("21:00", "21:50")
            ]
            let summer = [
                ("08:00", "08:50"), ("09:00", "09:50"), ("10:10", "11:00"),
                ("11:10", "12:00"), ("13:00", "13:50"), ("14:00", "14:20"),
                ("14:30", "15:20"), ("15:30", "16:20"), ("16:30", "17:20"),
                ("17:30", "18:20"), ("19:00", "19:50"), ("20:00", "20:50"),
                ("21:00", "21:50")
            ]
            let standard = (season ?? inferredSeason(for: semester)) == .summer ? summer : winter
            guard section <= standard.count else { return nil }
            let pair = standard[section - 1]
            return OfflineSectionTime(start: pair.0, end: pair.1)
        }
        guard section <= semester.sectionTimes.count else { return nil }
        return semester.sectionTimes[section - 1]
    }

    public static func inferredSeason(for semester: OfflineSemester) -> CampusScheduleSeason {
        let month = Int(semester.startDate.dropFirst(5).prefix(2)) ?? 1
        return (7...12).contains(month) ? .summer : .winter
    }

    /// Computes the academic week from the semester's local calendar date.
    /// Dates before the start remain outside the active range (nil).
    public static func academicWeek(
        for date: Date,
        semester: OfflineSemester,
        calendar: Calendar = OfflineDatePolicy.businessCalendar
    ) -> Int? {
        guard let start = calendarDate(semester.startDate, calendar: calendar) else { return nil }
        let days = calendar.dateComponents([.day], from: start, to: date).day ?? -1
        guard days >= 0 else { return nil }
        let week = days / 7 + 1
        return week <= semester.weekCount ? week : nil
    }

    private static func calendarDate(_ value: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
