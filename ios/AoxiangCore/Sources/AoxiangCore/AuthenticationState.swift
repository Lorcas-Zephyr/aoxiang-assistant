import Foundation

public enum AuthenticationOperation: String, Codable, Equatable {
    case login
    case collection
}

public enum AuthenticationFailureReason: String, Codable, Equatable {
    case networkUnavailable
    case serverUnavailable
    case rateLimited
    case invalidResponse
}

public struct RetryableAuthenticationFailure: Codable, Equatable {
    public let operation: AuthenticationOperation
    public let reason: AuthenticationFailureReason

    public init(operation: AuthenticationOperation, reason: AuthenticationFailureReason) {
        self.operation = operation
        self.reason = reason
    }
}

public enum AuthenticationAttentionReason: String, Codable, Equatable {
    case loginRequired
    case collectionNotReady
    case invalidCredentials
    case invalidSMS
    case authenticationExpired
    case smsRequired
}

public enum AuthenticationState: Equatable, Codable {
    case needsLogin
    case needsSMS
    case authenticated
    case readyToCollect
    case retryableFailure(RetryableAuthenticationFailure)
    case needsUserAttention(reason: AuthenticationAttentionReason)

    private enum CodingKeys: String, CodingKey { case state, failure, reason }
    private enum StateValue: String, Codable {
        case needsLogin
        case needsSMS
        case authenticated
        case readyToCollect
        case retryableFailure
        case needsUserAttention
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let state = try values.decode(StateValue.self, forKey: .state)
        switch state {
        case .needsLogin: self = .needsLogin
        case .needsSMS: self = .needsSMS
        case .authenticated: self = .authenticated
        case .readyToCollect: self = .readyToCollect
        case .retryableFailure:
            self = .retryableFailure(try values.decode(RetryableAuthenticationFailure.self, forKey: .failure))
        case .needsUserAttention:
            self = .needsUserAttention(reason: try values.decode(AuthenticationAttentionReason.self, forKey: .reason))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .needsLogin: try values.encode(StateValue.needsLogin, forKey: .state)
        case .needsSMS: try values.encode(StateValue.needsSMS, forKey: .state)
        case .authenticated: try values.encode(StateValue.authenticated, forKey: .state)
        case .readyToCollect: try values.encode(StateValue.readyToCollect, forKey: .state)
        case .retryableFailure(let failure):
            try values.encode(StateValue.retryableFailure, forKey: .state)
            try values.encode(failure, forKey: .failure)
        case .needsUserAttention(let reason):
            try values.encode(StateValue.needsUserAttention, forKey: .state)
            try values.encode(reason, forKey: .reason)
        }
    }

    public var canCollect: Bool {
        if case .readyToCollect = self { return true }
        return false
    }
}

public enum AuthenticationEvent: Equatable {
    case authenticationSucceeded
    case smsRequired
    case smsVerified
    case credentialsRejected
    case smsRejected
    case authenticationExpired
    case prepareToCollect
    case retryableFailure(RetryableAuthenticationFailure)
    case retry
    case userAttentionRequired(AuthenticationAttentionReason)
    case userAttentionAcknowledged
}

public enum AuthenticationTransitionError: Error, Equatable {
    case invalidTransition(from: AuthenticationState, event: AuthenticationEvent)
}

extension AuthenticationTransitionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let state, let event):
            return "Invalid authentication transition from \(state) with \(event)"
        }
    }
}

/// Explicit state machine for foreground authentication and collection gates.
/// It carries metadata only; credentials, cookies and SMS values never enter it.
public struct AuthenticationStateMachine {
    public private(set) var state: AuthenticationState

    public init(initialState: AuthenticationState = .needsLogin) {
        self.state = initialState
    }

    public func canHandle(_ event: AuthenticationEvent) -> Bool {
        var copy = self
        do {
            _ = try copy.handle(event)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public mutating func handle(_ event: AuthenticationEvent) throws -> AuthenticationState {
        let next: AuthenticationState?
        switch (state, event) {
        case (.needsLogin, .authenticationSucceeded): next = .authenticated
        case (.needsLogin, .smsRequired): next = .needsSMS
        case (.needsLogin, .credentialsRejected): next = .needsUserAttention(reason: .invalidCredentials)
        case (.needsLogin, .retryableFailure(let failure)): next = .retryableFailure(failure)

        case (.needsSMS, .smsVerified): next = .authenticated
        case (.needsSMS, .smsRejected): next = .needsUserAttention(reason: .invalidSMS)
        case (.needsSMS, .retryableFailure(let failure)): next = .retryableFailure(failure)
        case (.needsSMS, .userAttentionRequired(let reason)): next = .needsUserAttention(reason: reason)

        case (.authenticated, .prepareToCollect): next = .readyToCollect
        case (.authenticated, .authenticationExpired): next = .needsUserAttention(reason: .authenticationExpired)
        case (.authenticated, .smsRequired): next = .needsSMS
        case (.authenticated, .retryableFailure(let failure)): next = .retryableFailure(failure)

        case (.readyToCollect, .authenticationExpired): next = .needsUserAttention(reason: .authenticationExpired)
        case (.readyToCollect, .smsRequired): next = .needsUserAttention(reason: .smsRequired)
        case (.readyToCollect, .retryableFailure(let failure)): next = .retryableFailure(failure)
        case (.readyToCollect, .userAttentionRequired(let reason)): next = .needsUserAttention(reason: reason)

        case (.retryableFailure(let failure), .retry):
            next = failure.operation == .login ? .needsLogin : .readyToCollect
        case (.retryableFailure(_), .retryableFailure(let replacement)): next = .retryableFailure(replacement)
        case (.retryableFailure(let failure), .userAttentionAcknowledged):
            next = failure.operation == .login ? .needsLogin : .readyToCollect

        case (.needsUserAttention(let reason), .userAttentionAcknowledged):
            switch reason {
            case .invalidSMS, .smsRequired: next = .needsSMS
            case .collectionNotReady: next = .authenticated
            default: next = .needsLogin
            }
        case (.needsUserAttention(_), .retryableFailure(let failure)): next = .retryableFailure(failure)

        default: next = nil
        }
        guard let next else { throw AuthenticationTransitionError.invalidTransition(from: state, event: event) }
        state = next
        return next
    }
}
