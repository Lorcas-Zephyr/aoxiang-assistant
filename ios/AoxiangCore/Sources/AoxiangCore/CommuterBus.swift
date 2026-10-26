import Foundation

public struct CommuterBusRoute: Codable, Equatable, Identifiable {
    public var id: String
    public var type: String
    public var name: String
    public var startStation: String
    public var endStation: String
    public var studentCharge: String
    public var staffCharge: String

    public init(
        id: String = "",
        type: String = "",
        name: String = "",
        startStation: String = "",
        endStation: String = "",
        studentCharge: String = "",
        staffCharge: String = ""
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.startStation = startStation
        self.endStation = endStation
        self.studentCharge = studentCharge
        self.staffCharge = staffCharge
    }

    public var stationText: String {
        guard !startStation.isEmpty || !endStation.isEmpty else { return "" }
        return "\(startStation) → \(endStation)"
    }

    public var chargeText: String {
        [
            studentCharge.isEmpty ? nil : "学生 \(studentCharge) 元",
            staffCharge.isEmpty ? nil : "教职工 \(staffCharge) 元"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

public struct CommuterBusTrip: Codable, Equatable, Identifiable {
    public var id: String
    public var date: String
    public var routeID: String
    public var routeName: String
    public var departureTime: String
    public var capacity: Int
    public var bookedSeats: Int
    public var remainingSeats: Int?
    public var isReservable: Bool
    public var deadline: String
    public var hint: String
    public var note: String

    public init(
        id: String = "",
        date: String = "",
        routeID: String = "",
        routeName: String = "",
        departureTime: String = "",
        capacity: Int = 0,
        bookedSeats: Int = 0,
        remainingSeats: Int? = nil,
        isReservable: Bool = false,
        deadline: String = "",
        hint: String = "",
        note: String = ""
    ) {
        self.id = id
        self.date = date
        self.routeID = routeID
        self.routeName = routeName
        self.departureTime = departureTime
        self.capacity = capacity
        self.bookedSeats = bookedSeats
        self.remainingSeats = remainingSeats
        self.isReservable = isReservable
        self.deadline = deadline
        self.hint = hint
        self.note = note
    }

    public var seatText: String {
        guard isReservable else { return "已截止" }
        guard let remainingSeats else { return "余位未知" }
        return "余 \(remainingSeats) / \(capacity)"
    }

    public func departureDate(timeZone: TimeZone = CommuterBusDatePolicy.timeZone) -> Date? {
        CommuterBusDatePolicy.date(date: date, time: departureTime, timeZone: timeZone)
    }
}

public struct CommuterBusReservation: Codable, Equatable, Identifiable {
    public var id: String
    public var status: String
    public var reviewer: String
    public var routeName: String
    public var date: String
    public var departureTime: String
    public var driverPhone: String
    public var fee: String
    public var noticeURL: String

    public init(
        id: String = "",
        status: String = "",
        reviewer: String = "",
        routeName: String = "",
        date: String = "",
        departureTime: String = "",
        driverPhone: String = "",
        fee: String = "",
        noticeURL: String = ""
    ) {
        self.id = id
        self.status = status
        self.reviewer = reviewer
        self.routeName = routeName
        self.date = date
        self.departureTime = departureTime
        self.driverPhone = driverPhone
        self.fee = fee
        self.noticeURL = noticeURL
    }

    public var title: String { routeName.isEmpty ? "校车预约" : routeName }
    public var displaySummary: String { fee.isEmpty ? "" : "费用 \(fee) 元" }
    public var isRejected: Bool {
        status.contains("驳回") || status.contains("取消") || status.contains("失效")
    }
    public var isPending: Bool { status.contains("待") || status.contains("未") }

    public var whenText: String {
        let day: String
        if let parsed = CommuterBusDatePolicy.parseDate(date),
           let today = CommuterBusDatePolicy.parseDate(CommuterBusDatePolicy.today()) {
            if parsed == today { day = "今天" }
            else if let tomorrow = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: today),
                    parsed == tomorrow {
                day = "明天"
            } else {
                day = "\(Calendar(identifier: .gregorian).component(.month, from: parsed))月\(Calendar(identifier: .gregorian).component(.day, from: parsed))日"
            }
        } else {
            day = date
        }
        return [day, departureTime].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public func departureDate(timeZone: TimeZone = CommuterBusDatePolicy.timeZone) -> Date? {
        CommuterBusDatePolicy.date(date: date, time: departureTime, timeZone: timeZone)
    }
}

/// Local-only bus data. It is deliberately absent from Android backup documents.
public struct CommuterBusSnapshot: Codable, Equatable {
    public var updatedAt: Int64
    public var reserveDays: Int
    public var routes: [CommuterBusRoute]
    public var trips: [CommuterBusTrip]
    public var reservations: [CommuterBusReservation]

    public init(
        updatedAt: Int64 = 0,
        reserveDays: Int = 0,
        routes: [CommuterBusRoute] = [],
        trips: [CommuterBusTrip] = [],
        reservations: [CommuterBusReservation] = []
    ) {
        self.updatedAt = updatedAt
        self.reserveDays = reserveDays
        self.routes = routes
        self.trips = trips
        self.reservations = reservations
    }

    public func trips(on date: String) -> [CommuterBusTrip] {
        trips.filter { $0.date == date }
    }

    public func nextReservation(now: Date = Date()) -> CommuterBusReservation? {
        reservations
            .filter { !$0.isRejected }
            .filter { ($0.departureDate() ?? .distantPast) >= now }
            .min { ($0.departureDate() ?? .distantFuture) < ($1.departureDate() ?? .distantFuture) }
    }

    public func nextOpenTrip(now: Date = Date()) -> CommuterBusTrip? {
        trips
            .filter(\.isReservable)
            .filter { ($0.departureDate() ?? .distantPast) >= now }
            .min { ($0.departureDate() ?? .distantFuture) < ($1.departureDate() ?? .distantFuture) }
    }

    public func validated() throws -> CommuterBusSnapshot {
        guard updatedAt >= 0, reserveDays >= 0 else {
            throw OfflineDataError.invalidField("commuterBus")
        }
        try Self.validateIDs(routes.map(\.id), field: "commuterBus.routes")
        try Self.validateIDs(trips.map(\.id), field: "commuterBus.trips")
        try Self.validateIDs(reservations.map(\.id), field: "commuterBus.reservations")
        for trip in trips {
            guard trip.capacity >= 0, trip.bookedSeats >= 0,
                  trip.remainingSeats.map({ $0 >= 0 && (trip.capacity == 0 || $0 <= trip.capacity) }) ?? true else {
                throw OfflineDataError.invalidField("commuterBus.trip.seats")
            }
        }
        return self
    }

    private static func validateIDs(_ values: [String], field: String) throws {
        var seen = Set<String>()
        for value in values {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OfflineDataError.invalidField("\(field).id")
            }
            guard seen.insert(value).inserted else {
                throw OfflineDataError.duplicateID(value)
            }
        }
    }
}

public struct CommuterBusSyncResult: Equatable {
    public let snapshot: CommuterBusSnapshot
    public let routesComplete: Bool
    public let reservationsComplete: Bool
    public let tripsComplete: Bool

    public var hasUpdate: Bool { routesComplete || reservationsComplete || tripsComplete }

    public init(
        snapshot: CommuterBusSnapshot,
        routesComplete: Bool,
        reservationsComplete: Bool,
        tripsComplete: Bool
    ) {
        self.snapshot = snapshot
        self.routesComplete = routesComplete
        self.reservationsComplete = reservationsComplete
        self.tripsComplete = tripsComplete
    }
}

public enum CommuterBusSyncMerger {
    public static func merge(
        payload: Data,
        previous: CommuterBusSnapshot = CommuterBusSnapshot(),
        updatedAt: Int64,
        today: String
    ) throws -> CommuterBusSyncResult {
        guard let root = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw OfflineDataError.invalidField("commuterBus.payload")
        }
        let routeResponse = object(root["routes"])
        let reservationResponse = object(root["reservations"])
        let routeData = object(routeResponse?["data"])
        let reservationData = object(reservationResponse?["data"])
        let routeItems = routeData?["filteredBusRoutes"] as? [[String: Any]]
        let reservationItems = (reservationData?["list"] ?? reservationData?["List"]) as? [[String: Any]]
        let tripGroups = root["tripGroups"] as? [[String: Any]]

        let routesComplete = boolean(root["routesComplete"])
            ?? (isSuccess(routeResponse) && routeItems != nil)
        let reservationsComplete = boolean(root["reservationsComplete"])
            ?? (isSuccess(reservationResponse) && reservationItems != nil)
        let tripsComplete = boolean(root["tripsComplete"]) ?? (tripGroups != nil)

        var next = previous
        next.updatedAt = updatedAt
        if routesComplete {
            next.routes = parseRoutes(routeItems ?? [])
            next.reserveDays = positiveInt(object(routeData?["reservationDays"])?["TQYYXZTS"])
        }
        if reservationsComplete {
            next.reservations = parseReservations(reservationItems ?? [])
        }
        if tripsComplete {
            next.trips = parseTrips(tripGroups ?? [])
                .filter { $0.date >= today }
                .sorted { ($0.date, $0.departureTime, $0.routeName) < ($1.date, $1.departureTime, $1.routeName) }
        }
        return CommuterBusSyncResult(
            snapshot: try next.validated(),
            routesComplete: routesComplete,
            reservationsComplete: reservationsComplete,
            tripsComplete: tripsComplete
        )
    }

    private static func parseRoutes(_ items: [[String: Any]]) -> [CommuterBusRoute] {
        items.compactMap { item in
            let route = CommuterBusRoute(
                id: text(item, "Objid", "objId", "ObjId"),
                type: text(item, "Type", "type"),
                name: text(item, "Name", "name"),
                startStation: text(item, "StartStation", "startStation"),
                endStation: text(item, "EndStation", "endStation"),
                studentCharge: text(item, "StudentCharge", "studentCharge"),
                staffCharge: text(item, "TeacherStaffCharge", "teacherStaffCharge")
            )
            var normalized = route
            if normalized.id.isEmpty { normalized.id = normalized.name }
            return normalized.id.isEmpty ? nil : normalized
        }
    }

    private static func parseTrips(_ groups: [[String: Any]]) -> [CommuterBusTrip] {
        var results: [CommuterBusTrip] = []
        var seen = Set<String>()
        for group in groups {
            let date = CommuterBusDatePolicy.normalizeDate(text(group, "date", "Date"))
            let routeID = text(group, "routeId", "RouteId")
            let routeName = text(group, "routeName", "RouteName")
            for item in (group["items"] as? [[String: Any]] ?? []) {
                let objID = text(item, "objId", "Objid")
                let time = CommuterBusDatePolicy.normalizeTime(text(item, "fcsj", "FCSJ"))
                let id = objID.isEmpty ? "\(date)|\(routeID)|\(time)" : objID
                guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, seen.insert(id).inserted else {
                    continue
                }
                let booked = positiveInt(item["yyrs"])
                let capacity = positiveInt(item["kyyrs"])
                results.append(CommuterBusTrip(
                    id: id,
                    date: date,
                    routeID: routeID,
                    routeName: routeName,
                    departureTime: time,
                    capacity: capacity,
                    bookedSeats: booked,
                    remainingSeats: capacity > 0 ? max(0, capacity - booked) : nil,
                    isReservable: boolean(item["sfkyy"]) ?? false,
                    deadline: text(item, "yyjzxx", "YYJZXX"),
                    hint: text(item, "tsxx", "TSXX"),
                    note: text(item, "bcms", "BCMS")
                ))
            }
        }
        return results
    }

    private static func parseReservations(_ items: [[String: Any]]) -> [CommuterBusReservation] {
        var results: [CommuterBusReservation] = []
        var seen = Set<String>()
        for item in items {
            let routeName = text(item, "xlmc", "XLMC", "routeName", "lineName", "Name", "name")
            let date = CommuterBusDatePolicy.normalizeDate(text(item, "ccrq", "CCRQ", "yyrq", "YYRQ", "date", "Date"))
            let time = CommuterBusDatePolicy.normalizeTime(text(item, "fcsj", "FCSJ", "sjd", "SJD", "time", "Time"))
            let orderID = text(item, "yydh", "YYDH", "orderNo", "OrderNo", "yybh")
            let id = orderID.isEmpty ? "\(routeName)|\(date)|\(time)" : orderID
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, seen.insert(id).inserted else {
                continue
            }
            results.append(CommuterBusReservation(
                id: id,
                status: text(item, "yyzt", "YYZT", "status", "Status"),
                reviewer: text(item, "shr", "SHR", "reviewer"),
                routeName: routeName,
                date: date,
                departureTime: time,
                driverPhone: text(item, "yktyfddh", "YKTYFDDH", "driverPhone"),
                fee: text(item, "fy", "FY", "fee"),
                noticeURL: text(item, "yyxz", "YYXZ", "noticeUrl")
            ))
        }
        return results
    }

    private static func object(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

    private static func isSuccess(_ response: [String: Any]?) -> Bool {
        boolean(response?["isSuccess"]) == true
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? String {
            if value.caseInsensitiveCompare("true") == .orderedSame { return true }
            if value.caseInsensitiveCompare("false") == .orderedSame { return false }
        }
        return nil
    }

    private static func text(_ object: [String: Any], _ keys: String...) -> String {
        for key in keys {
            guard let value = object[key], !(value is NSNull) else { continue }
            let result = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            if !result.isEmpty, result != "null" { return result }
        }
        return ""
    }

    private static func positiveInt(_ value: Any?) -> Int {
        guard let value, !(value is NSNull) else { return 0 }
        let digits = String(describing: value).filter(\.isNumber)
        return max(0, Int(digits) ?? 0)
    }
}

public enum CommuterBusDatePolicy {
    public static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    public static func today(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }

    public static func parseDate(_ value: String) -> Date? {
        let datePart = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init) ?? value
        for format in ["yyyy-MM-dd", "yyyy/M/d", "yyyy/MM/dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: datePart) { return date }
        }
        return nil
    }

    public static func normalizeDate(_ value: String) -> String {
        guard let date = parseDate(value) else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func normalizeTime(_ value: String) -> String {
        var timePart = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = timePart.lastIndex(of: "T") { timePart = String(timePart[timePart.index(after: separator)...]) }
        let parts = timePart.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return value }
        return String(format: "%02d:%02d", hour, minute)
    }

    public static func date(date: String, time: String, timeZone: TimeZone = timeZone) -> Date? {
        let normalizedDate = normalizeDate(date)
        let normalizedTime = normalizeTime(time)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(normalizedDate) \(normalizedTime)")
    }
}

public enum CommuterBusReminderPolicy {
    public static let departureLeadInterval: TimeInterval = 30 * 60

    public static func canRemindDeparture(for reservation: CommuterBusReservation) -> Bool {
        let status = reservation.status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !status.isEmpty,
              !["待核验", "待审核", "待审批", "待处理", "取消", "撤销", "拒绝", "未通过", "失败"]
                .contains(where: status.contains) else {
            return false
        }
        return ["通过", "成功", "已预约", "待乘车", "已确认"].contains(where: status.contains)
    }

    public static func departureReminderDate(for reservation: CommuterBusReservation) -> Date? {
        guard canRemindDeparture(for: reservation),
              let departure = reservation.departureDate() else { return nil }
        return departure.addingTimeInterval(-departureLeadInterval)
    }

    public static func shouldRemindDeparture(at departure: Date?, now: Date) -> Bool {
        guard let departure else { return false }
        let remaining = departure.timeIntervalSince(now)
        return remaining >= 0 && remaining <= departureLeadInterval
    }

    public static func statusChanges(
        previous: [CommuterBusReservation],
        current: [CommuterBusReservation]
    ) -> [CommuterBusReservation] {
        let previousStatuses = Dictionary(previous.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
        return current.filter { reservation in
            guard let previousStatus = previousStatuses[reservation.id],
                  previousStatus != reservation.status else { return false }
            return !reservation.status.contains("待核验") && !reservation.status.contains("待审核")
        }
    }
}
