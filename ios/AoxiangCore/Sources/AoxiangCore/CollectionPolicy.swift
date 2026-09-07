import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CollectionCapability: String, Codable, Equatable {
    case stableHTTP
    case pageJavaScript
}

public enum CollectionTransport: String, Codable, Equatable {
    case urlSession
    case visibleWebView
}

public enum CollectionDecision: Equatable {
    case needsLogin
    case needsSMS
    case use(CollectionTransport)
    case retryable(RetryableAuthenticationFailure)
    case blocked(AuthenticationAttentionReason)
}

public enum CollectionPolicy {
    public static func decide(
        state: AuthenticationState,
        capability: CollectionCapability
    ) -> CollectionDecision {
        switch state {
        case .needsLogin:
            return .needsLogin
        case .needsSMS:
            return .needsSMS
        case .retryableFailure(let failure):
            return .retryable(failure)
        case .needsUserAttention(let reason):
            return .blocked(reason)
        case .authenticated:
            return .blocked(.collectionNotReady)
        case .readyToCollect:
            return .use(capability == .stableHTTP ? .urlSession : .visibleWebView)
        }
    }
}

public struct StableHTTPCollectionRequest: Equatable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public protocol StableHTTPCollectionPort {
    func send(_ request: StableHTTPCollectionRequest) async throws -> (Data, HTTPURLResponse)
}

public enum CollectionTransportError: Error, Equatable {
    case unstableEndpoint
    case authenticationRequired
    case smsRequired
    case retryable(AuthenticationFailureReason)
    case nonSuccessStatus(Int)
    case cancelled
}

/// A small policy-driven entry point that prevents accidental use of HTTP for
/// page-JavaScript endpoints and prevents collection before authentication.
public struct ForegroundCollectionPlanner {
    public init() {}

    public func plan(
        state: AuthenticationState,
        capability: CollectionCapability
    ) -> CollectionDecision {
        CollectionPolicy.decide(state: state, capability: capability)
    }
}
