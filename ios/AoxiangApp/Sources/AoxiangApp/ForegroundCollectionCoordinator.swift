import Foundation
import AoxiangCore

public enum ForegroundCollectionResult: Equatable {
    case data(Data)
    case needsVisibleAuthentication
    case needsSMS
    case retryable(AuthenticationFailureReason)
}

/// Shared coordinator for foreground collection. It routes stable endpoints to
/// URLSession and leaves JavaScript-dependent endpoints in the visible WebView.
public final class ForegroundCollectionCoordinator {
    private let planner: ForegroundCollectionPlanner
    private let http: StableHTTPCollectionPort

    public init(
        planner: ForegroundCollectionPlanner = ForegroundCollectionPlanner(),
        http: StableHTTPCollectionPort
    ) {
        self.planner = planner
        self.http = http
    }

    public func collect(
        state: AuthenticationState,
        capability: CollectionCapability,
        request: StableHTTPCollectionRequest
    ) async -> ForegroundCollectionResult {
        switch planner.plan(state: state, capability: capability) {
        case .needsLogin, .blocked: return .needsVisibleAuthentication
        case .needsSMS: return .needsSMS
        case .retryable(let failure): return .retryable(failure.reason)
        case .use(.visibleWebView): return .needsVisibleAuthentication
        case .use(.urlSession):
            do {
                let (data, _) = try await http.send(request)
                return .data(data)
            } catch CollectionTransportError.authenticationRequired {
                return .needsVisibleAuthentication
            } catch CollectionTransportError.retryable(let reason) {
                return .retryable(reason)
            } catch CollectionTransportError.nonSuccessStatus(let status) {
                if status == 429 {
                    return .retryable(.rateLimited)
                }
                if status == 408 || (500...599).contains(status) {
                    return .retryable(.serverUnavailable)
                }
                return .retryable(.invalidResponse)
            } catch {
                return .retryable(.invalidResponse)
            }
        }
    }
}
