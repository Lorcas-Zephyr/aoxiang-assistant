import Foundation

public enum PortalCollectionWarning: String, Equatable {
    case electricityUnavailable
    case scheduleUnavailable
}

/// A sanitized, actionable reason why the independent electricity read did
/// not produce a balance. This is deliberately separate from the coarse
/// warning used by older UI surfaces so authentication and retry actions are
/// not lost when grades or schedule data are still valid.
public enum ElectricityCollectionIssue: Equatable, Codable {
    case needsLogin
    case needsSMS
    case retryable(AuthenticationFailureReason)
    case invalidResponse(String)
    case settlement

    private enum CodingKeys: String, CodingKey {
        case kind
        case reason
        case message
    }

    private enum Kind: String, Codable {
        case needsLogin
        case needsSMS
        case retryable
        case invalidResponse
        case settlement
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .needsLogin:
            try container.encode(Kind.needsLogin, forKey: .kind)
        case .needsSMS:
            try container.encode(Kind.needsSMS, forKey: .kind)
        case .retryable(let reason):
            try container.encode(Kind.retryable, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        case .invalidResponse(let message):
            try container.encode(Kind.invalidResponse, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .settlement:
            try container.encode(Kind.settlement, forKey: .kind)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .needsLogin:
            self = .needsLogin
        case .needsSMS:
            self = .needsSMS
        case .retryable:
            self = .retryable(try container.decode(AuthenticationFailureReason.self, forKey: .reason))
        case .invalidResponse:
            self = .invalidResponse(try container.decode(String.self, forKey: .message))
        case .settlement:
            self = .settlement
        }
    }
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
    /// A precise, actionable electricity failure retained alongside the
    /// legacy warning. It never contains credentials, cookies or raw page
    /// responses.
    public let electricityIssue: ElectricityCollectionIssue?
    public let warnings: [PortalCollectionWarning]

    public init(
        grades: [OfflineGrade],
        gpa: Double? = nil,
        schedule: PortalCollectionParsers.SchedulePayload,
        electricityBalance: Double? = nil,
        electricityIssue: ElectricityCollectionIssue? = nil,
        warnings: [PortalCollectionWarning] = [],
        scheduleAvailable: Bool = true
    ) {
        self.grades = grades
        self.gpa = gpa
        self.schedule = schedule
        self.electricityBalance = electricityBalance
        self.electricityIssue = electricityIssue
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
    case settlement
    case cancelled
}

extension PortalCollectionFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authenticationRequired: return "认证已失效，请重新登录"
        case .smsRequired: return "需要短信验证，请在前台完成验证"
        case .retryable(let reason): return "采集暂时失败：\(reason.rawValue)"
        case .invalidResponse(let value): return "采集数据无效：\(value)"
        case .settlement: return "电费系统正在结算，请在 1:00 后重试"
        case .cancelled: return "采集已取消"
        }
    }
}
