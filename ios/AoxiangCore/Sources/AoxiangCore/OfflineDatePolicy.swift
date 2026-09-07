import Foundation

/// Shared business calendar for wire-format dates and timetable evaluation.
/// The iPhone or iPad's display timezone must not change the academic day.
public enum OfflineDatePolicy {
    public static let businessTimeZoneIdentifier = "Asia/Shanghai"

    public static var businessCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        if let timeZone = TimeZone(identifier: businessTimeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        return calendar
    }
}
