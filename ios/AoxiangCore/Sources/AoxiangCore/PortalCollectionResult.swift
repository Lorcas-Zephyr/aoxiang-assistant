import Foundation

public enum PortalCollectionWarning: String, Equatable {
    case electricityUnavailable
    case scheduleUnavailable
}

/// A complete, sanitized foreground collection candidate. It contains only
/// domain values and can therefore cross the App/Core boundary without
/// carrying credentials, cookies, WebView state or raw responses.
public struct PortalCollectedData: Equatable {
    public let grades: [OfflineGrade]
    public let gpa: Double?
    public let schedule: PortalCollectionParsers.SchedulePayload
    /// `false` means the education response contained valid grades but the
    /// schedule endpoint was unavailable. Callers must preserve the existing
    /// local schedule in that case.
    public let scheduleAvailable: Bool
    /// The latest balance when the electricity page was readable. It is
    /// optional so a successful grades/schedule collection can still be
    /// committed when the separate electricity portal is unavailable.
    public let electricityBalance: Double?
    public let warnings: [PortalCollectionWarning]

    public init(
        grades: [OfflineGrade],
        gpa: Double? = nil,
        schedule: PortalCollectionParsers.SchedulePayload,
        electricityBalance: Double? = nil,
        warnings: [PortalCollectionWarning] = [],
        scheduleAvailable: Bool = true
    ) {
        self.grades = grades
        self.gpa = gpa
        self.schedule = schedule
        self.electricityBalance = electricityBalance
        self.warnings = warnings
        self.scheduleAvailable = scheduleAvailable
    }
}

/// Sanitized education data returned by the visible, same-origin WebView
/// collector. Raw HTML, cookies, credentials and WebView state never cross
/// this boundary; only values already accepted by the portable parsers do.
public struct PortalVisibleEducationData: Equatable {
    public let grades: [OfflineGrade]
    public let gpa: Double?
    public let schedule: PortalCollectionParsers.SchedulePayload
    public let scheduleAvailable: Bool

    public init(
        grades: [OfflineGrade],
        gpa: Double? = nil,
        schedule: PortalCollectionParsers.SchedulePayload,
        scheduleAvailable: Bool = true
    ) {
        self.grades = grades
        self.gpa = gpa
        self.schedule = schedule
        self.scheduleAvailable = scheduleAvailable
    }
}

public enum PortalCollectionPhase: String, Codable, Equatable {
    case idle
    case collecting
    case succeeded
    case needsLogin
    case needsSMS
    case retryableFailure
    case failed
}

public enum PortalCollectionFailure: Error, Equatable {
    case authenticationRequired
    case smsRequired
    case retryable(AuthenticationFailureReason)
    case invalidResponse(String)
    case cancelled
}

extension PortalCollectionFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authenticationRequired: return "认证已失效，请重新登录"
        case .smsRequired: return "需要短信验证，请在前台完成验证"
        case .retryable(let reason): return "采集暂时失败：\(reason.rawValue)"
        case .invalidResponse(let value): return "采集数据无效：\(value)"
        case .cancelled: return "采集已取消"
        }
    }
}
