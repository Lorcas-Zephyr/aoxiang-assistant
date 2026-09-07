import Foundation

/// Thread-safe, credential-free authentication state shared by the visible
/// WebView and best-effort background coordination. It deliberately stores
/// only the state-machine value; passwords, cookies, tokens and SMS values do
/// not have a representation here.
public final class AuthenticationSessionStore {
    private let lock = NSLock()
    private var storedState: AuthenticationState

    public init(initialState: AuthenticationState = .needsLogin) {
        storedState = initialState
    }

    public var state: AuthenticationState {
        lock.lock()
        defer { lock.unlock() }
        return storedState
    }

    public func set(_ state: AuthenticationState) {
        lock.lock()
        storedState = state
        lock.unlock()
    }
}
