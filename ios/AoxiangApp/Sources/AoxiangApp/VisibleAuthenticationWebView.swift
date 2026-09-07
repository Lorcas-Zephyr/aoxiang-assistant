import Foundation
import AoxiangCore

#if canImport(WebKit)
import WebKit
#endif

#if os(iOS) && canImport(SwiftUI) && canImport(WebKit)
import SwiftUI

public struct AuthenticationSuccessRule: Equatable {
    public let hostSuffix: String
    public let pathPrefixes: [String]
    public let bodyMarkers: [String]

    public init(
        hostSuffix: String,
        pathPrefixes: [String] = [],
        bodyMarkers: [String] = []
    ) {
        self.hostSuffix = hostSuffix
        self.pathPrefixes = pathPrefixes
        self.bodyMarkers = bodyMarkers
    }

    public static let jwxtStudentHome = AuthenticationSuccessRule(
        hostSuffix: "jwxt.nwpu.edu.cn",
        pathPrefixes: ["/student/home"]
    )
}

/// A visible, user-driven authentication surface. Credentials are typed by the
/// user into the page and are never copied into this view model or any backup.
@MainActor
public final class VisibleAuthenticationViewModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published public private(set) var state: AuthenticationState = .needsLogin
    @Published public private(set) var lastError: String?

    public let webView: WKWebView
    private var machine = AuthenticationStateMachine()
    private let loginURL: URL
    private let successRule: AuthenticationSuccessRule
    private let sessionStore: AuthenticationSessionStore
    private var lastInspectedURL: URL?
    private var stateDetectionInFlight = false

    public init(
        loginURL: URL,
        successRule: AuthenticationSuccessRule = .jwxtStudentHome,
        sessionStore: AuthenticationSessionStore = AuthenticationSessionStore(),
        websiteDataStore: WKWebsiteDataStore = .default()
    ) {
        let initialState = sessionStore.state
        self.loginURL = loginURL
        self.successRule = successRule
        self.sessionStore = sessionStore
        self.state = initialState
        self.machine = AuthenticationStateMachine(initialState: initialState)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    public func startInteractiveLogin() {
        machine = AuthenticationStateMachine()
        state = machine.state
        sessionStore.set(state)
        lastError = nil
        lastInspectedURL = nil
        stateDetectionInFlight = false
        webView.load(URLRequest(url: loginURL))
    }

    public func acknowledgeAttention() {
        do {
            state = try machine.handle(.userAttentionAcknowledged)
            sessionStore.set(state)
        }
        catch { lastError = error.localizedDescription }
    }

    /// Explicit foreground gate between a successful login page and collection.
    /// Background tasks can only run after this action has been completed.
    public func prepareToCollect() {
        transition(.prepareToCollect)
    }

    /// Returns cookie names only. Values are deliberately inaccessible to the
    /// portable layer and are never serialized.
    public func sessionCookieNames(completion: @escaping ([String]) -> Void) {
        let loginHost = self.loginURL.host ?? ""
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let names = cookies
                .filter { AoxiangCookieScope.belongsToHost($0, host: loginHost) }
                .map(\.name)
                .sorted()
            DispatchQueue.main.async { completion(names) }
        }
    }

    public func clearSessionCookies(completion: (() -> Void)? = nil) {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let loginHost = self.loginURL.host ?? ""
        store.getAllCookies { cookies in
            let group = DispatchGroup()
            for cookie in cookies where AoxiangCookieScope.belongsToHost(cookie, host: loginHost) {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                self.machine = AuthenticationStateMachine()
                self.state = self.machine.state
                self.sessionStore.set(self.state)
                completion?()
            }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        detectAuthenticationState(in: webView)
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        lastError = error.localizedDescription
        transition(.retryableFailure(RetryableAuthenticationFailure(
            operation: .login,
            reason: .networkUnavailable
        )))
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        lastError = error.localizedDescription
        transition(.retryableFailure(RetryableAuthenticationFailure(
            operation: .login,
            reason: .networkUnavailable
        )))
    }

    private func detectAuthenticationState(in webView: WKWebView) {
        guard let url = webView.url else { return }
        guard !stateDetectionInFlight else { return }
        if lastInspectedURL == url {
            switch state {
            case .authenticated, .readyToCollect, .needsUserAttention:
                return
            case .needsLogin, .needsSMS, .retryableFailure:
                break
            }
        }
        lastInspectedURL = url
        let urlText = url.absoluteString.lowercased()
        if (urlText.contains("sms") || urlText.contains("verify")), state != .needsSMS {
            transition(.smsRequired)
            return
        }
        if urlText.contains("error") || urlText.contains("failed") {
            transition(.credentialsRejected)
            return
        }
        guard let host = url.host?.lowercased(), isAllowedHost(host) else {
            return
        }
        stateDetectionInFlight = true
        // The page remains visible. JavaScript is only a read-only marker check;
        // it never receives credentials or emits a hardware/network command.
        webView.evaluateJavaScript(
            "document.body ? document.body.innerText : ''",
            completionHandler: { [weak self] value, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.stateDetectionInFlight = false
                    if let error {
                        self.lastError = error.localizedDescription
                        return
                    }
                    let body = (value as? String ?? "").lowercased()
                    if body.contains("短信") || body.contains("sms") {
                        self.transition(.smsRequired)
                    } else if body.contains("密码错误") || body.contains("invalid") {
                        self.transition(.credentialsRejected)
                    } else if self.successRuleMatches(url: url, body: body) {
                        self.completeAuthentication()
                    }
                }
            }
        )
    }

    private func isAllowedHost(_ host: String) -> Bool {
        let suffix = successRule.hostSuffix.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == suffix || host.hasSuffix(".\(suffix)")
    }

    private func successRuleMatches(url: URL, body: String) -> Bool {
        guard isAllowedHost(url.host?.lowercased() ?? "") else { return false }
        let path = url.path.lowercased()
        let pathsMatch = successRule.pathPrefixes.isEmpty || successRule.pathPrefixes.contains {
            path.hasPrefix($0.lowercased())
        }
        guard pathsMatch else { return false }
        if successRule.bodyMarkers.isEmpty { return true }
        return successRule.bodyMarkers.contains { body.contains($0.lowercased()) }
    }

    private func transition(_ event: AuthenticationEvent) {
        do {
            state = try machine.handle(event)
            sessionStore.set(state)
        } catch {
            if isBenignDuplicate(event) { return }
            // A repeated navigation callback is harmless; illegal transitions
            // remain observable without changing the current state.
            lastError = error.localizedDescription
        }
    }

    private func completeAuthentication() {
        if case .needsSMS = state {
            transition(.smsVerified)
        } else {
            transition(.authenticationSucceeded)
        }
    }

    private func isBenignDuplicate(_ event: AuthenticationEvent) -> Bool {
        switch (state, event) {
        case (.authenticated, .authenticationSucceeded),
             (.readyToCollect, .authenticationSucceeded),
             (.needsSMS, .smsRequired),
             (.needsUserAttention(reason: .invalidCredentials), .credentialsRejected),
             (.needsUserAttention(reason: .invalidSMS), .smsRejected):
            return true
        default:
            return false
        }
    }
}

public struct VisibleAuthenticationWebView: UIViewRepresentable {
    public let model: VisibleAuthenticationViewModel
    public init(model: VisibleAuthenticationViewModel) { self.model = model }
    public func makeUIView(context: Context) -> WKWebView { model.webView }
    public func updateUIView(_ view: WKWebView, context: Context) {}
}

public struct AuthenticationScreen: View {
    @ObservedObject public var model: VisibleAuthenticationViewModel

    public init(model: VisibleAuthenticationViewModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            VisibleAuthenticationWebView(model: model)
            HStack {
                Text(statusText).font(.caption)
                Spacer()
                if model.state == .authenticated {
                    Button("准备采集") { model.prepareToCollect() }
                }
                Button("重新登录") { model.startInteractiveLogin() }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.12))
        }
        .onAppear { if model.state == .needsLogin { model.startInteractiveLogin() } }
    }

    private var statusText: String {
        switch model.state {
        case .needsLogin: return "需要登录"
        case .needsSMS: return "需要短信验证"
        case .authenticated: return "认证成功"
        case .readyToCollect: return "可继续采集"
        case .retryableFailure: return "可重试失败"
        case .needsUserAttention: return "需要处理"
        }
    }
}
#endif
