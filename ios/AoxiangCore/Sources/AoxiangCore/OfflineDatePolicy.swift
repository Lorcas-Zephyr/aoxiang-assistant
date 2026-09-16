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

    /// The card provider settles electricity readings during the first local
    /// hour of each business day. Keep this rule in the portable date policy
    /// so iOS and Android adapters do not accidentally use the device locale
    /// or UTC when deciding whether a read can be completed.
    public static func isElectricitySettlementTime(_ date: Date = Date()) -> Bool {
        businessCalendar.component(.hour, from: date) == 0
    }
}
