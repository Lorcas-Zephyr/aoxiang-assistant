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
    private var electricityContinuation: CheckedContinuation<Double, Error>?
    private var electricityTimeoutTask: Task<Void, Never>?
    private var portraitContinuation: CheckedContinuation<String?, Error>?
    private var portraitTimeoutTask: Task<Void, Never>?
    private let studentPortraitURL = URL(string: "https://jwxt.nwpu.edu.cn/student/for-std/student-portrait")!
    private let electricityLoginURL = URL(string: "https://yktapp.nwpu.edu.cn/berserker-auth/cas/login/supwisdom?targetUrl=https%3A%2F%2Fyktapp.nwpu.edu.cn%2Fplat")!

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

    /// Records a collection-side authentication result without accepting any
    /// credential or session value into the portable model.
    public func recordCollectionFailure(_ failure: PortalCollectionFailure) {
        switch failure {
        case .authenticationRequired:
            transition(.authenticationExpired)
        case .smsRequired:
            transition(.smsRequired)
        case .retryable(let reason):
            transition(.retryableFailure(RetryableAuthenticationFailure(
                operation: .collection,
                reason: reason
            )))
        case .invalidResponse, .cancelled:
            lastError = failure.localizedDescription
        }
    }

    /// Runs the electricity page in the same visible WebView/cookie store as
    /// authentication. Tokens remain inside page JavaScript; only the parsed
    /// non-sensitive balance crosses back to the app.
    public func collectElectricityBalance() async throws -> Double {
        guard state == .readyToCollect else {
            throw PortalCollectionFailure.invalidResponse("collection not prepared")
        }
        guard electricityContinuation == nil, portraitContinuation == nil else {
            throw PortalCollectionFailure.retryable(.invalidResponse)
        }
        return try await withCheckedThrowingContinuation { continuation in
            electricityContinuation = continuation
            electricityTimeoutTask?.cancel()
            electricityTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.finishElectricity(.failure(PortalCollectionFailure.retryable(.serverUnavailable)))
                }
            }
            webView.load(URLRequest(url: electricityLoginURL))
        }
    }

    /// Reads the student portrait through the visible WebView when the stable
    /// GPA endpoint has no usable value. Only the returned HTML text crosses
    /// into the collector; cookies, credentials and page state stay in WebKit.
    public func collectPortraitHTML() async throws -> String? {
        guard state == .readyToCollect else {
            throw PortalCollectionFailure.invalidResponse("collection not prepared")
        }
        guard electricityContinuation == nil, portraitContinuation == nil else {
            throw PortalCollectionFailure.retryable(.invalidResponse)
        }
        return try await withCheckedThrowingContinuation { continuation in
            portraitContinuation = continuation
            portraitTimeoutTask?.cancel()
            portraitTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.finishPortrait(.failure(PortalCollectionFailure.retryable(.serverUnavailable)))
                }
            }
            webView.load(URLRequest(url: studentPortraitURL))
        }
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
        handlePortraitNavigation(in: webView)
        handleElectricityNavigation(in: webView)
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
        if electricityContinuation != nil {
            finishElectricity(.failure(PortalCollectionFailure.retryable(.networkUnavailable)))
        }
        if portraitContinuation != nil {
            finishPortrait(.failure(PortalCollectionFailure.retryable(.networkUnavailable)))
        }
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
        if electricityContinuation != nil {
            finishElectricity(.failure(PortalCollectionFailure.retryable(.networkUnavailable)))
        }
        if portraitContinuation != nil {
            finishPortrait(.failure(PortalCollectionFailure.retryable(.networkUnavailable)))
        }
    }

    private func handlePortraitNavigation(in webView: WKWebView) {
        guard portraitContinuation != nil, let url = webView.url,
              url.host?.lowercased() == studentPortraitURL.host?.lowercased(),
              url.path.lowercased().hasPrefix(studentPortraitURL.path.lowercased()) else { return }
        webView.evaluateJavaScript("document.documentElement ? document.documentElement.outerHTML : ''") { [weak self] value, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.finishPortrait(.failure(PortalCollectionFailure.invalidResponse(error.localizedDescription)))
                } else {
                    self.finishPortrait(.success(value as? String))
                }
            }
        }
    }

    private func handleElectricityNavigation(in webView: WKWebView) {
        guard electricityContinuation != nil, let url = webView.url,
              url.host?.lowercased() == "yktapp.nwpu.edu.cn" else { return }
        let path = url.path.lowercased()
        if path.hasPrefix("/plat") {
            webView.evaluateJavaScript("""
            (() => {
              const token = new URL(location.href).searchParams.get('synjones-auth') || sessionStorage.getItem('access_token') || '';
              if (!token) return false;
              location.replace(location.origin + '/jfdt/charge/feeitem/toAppitem?feeitemid=182&synjones-auth=' + encodeURIComponent(token) + '&appId=36&loginFrom=h5&type=app');
              return true;
            })()
            """, completionHandler: nil)
            return
        }
        guard path.hasPrefix("/jfdt/") else { return }
        let script = """
        (() => {
          const labels = ['当前剩余电量','剩余电量','电费余额','剩余电费','剩余金额','电量余额'];
          const parse = value => {
            const match = String(value == null ? '' : value).match(/-?\\d+(?:\\.\\d+)?/);
            if (!match) return null;
            const number = Number.parseFloat(match[0]);
            return Number.isFinite(number) && number >= 0 && number < 100000 ? number : null;
          };
          const inspect = value => {
            if (!value || typeof value !== 'object') return null;
            for (const label of labels) {
              if (Object.prototype.hasOwnProperty.call(value, label)) {
                const parsed = parse(value[label]);
                if (parsed !== null) return parsed;
              }
            }
            return null;
          };
          const root = document.querySelector('#app') && document.querySelector('#app').__vue__;
          const queue = root ? [root] : [];
          const seen = new Set();
          while (queue.length && seen.size < 100) {
            const component = queue.shift();
            if (!component || seen.has(component)) continue;
            seen.add(component);
            const data = component.$data || {};
            const candidates = [component.aboutEleric && component.aboutEleric.electricInfo, data.aboutEleric && data.aboutEleric.electricInfo, component.electricInfo, data.electricInfo];
            for (const candidate of candidates) {
              const parsed = inspect(candidate);
              if (parsed !== null) return parsed;
            }
            (component.$children || []).forEach(child => queue.push(child));
          }
          const text = document.body ? document.body.innerText : '';
          const match = text.match(/(?:当前剩余电量|剩余电量|电费余额|剩余电费|剩余金额|电量余额)\\s*[：:]?\\s*(?:¥|￥)?\\s*(-?\\d+(?:\\.\\d+)?)/);
          return match ? parse(match[1]) : null;
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.finishElectricity(.failure(PortalCollectionFailure.invalidResponse(error.localizedDescription)))
                    return
                }
                if let number = value as? NSNumber {
                    self.finishElectricity(.success(number.doubleValue))
                }
            }
        }
    }

    private func finishElectricity(_ result: Result<Double, Error>) {
        electricityTimeoutTask?.cancel()
        electricityTimeoutTask = nil
        guard let continuation = electricityContinuation else { return }
        electricityContinuation = nil
        continuation.resume(with: result)
    }

    private func finishPortrait(_ result: Result<String?, Error>) {
        portraitTimeoutTask?.cancel()
        portraitTimeoutTask = nil
        guard let continuation = portraitContinuation else { return }
        portraitContinuation = nil
        continuation.resume(with: result)
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
    private let onPrepareToCollect: () -> Void

    public init(
        model: VisibleAuthenticationViewModel,
        onPrepareToCollect: (() -> Void)? = nil
    ) {
        self.model = model
        self.onPrepareToCollect = onPrepareToCollect ?? { model.prepareToCollect() }
    }

    public var body: some View {
        VStack(spacing: 0) {
            VisibleAuthenticationWebView(model: model)
            HStack {
                Text(statusText).font(.caption)
                Spacer()
                if model.state == .authenticated || model.state == .readyToCollect {
                    Button(model.state == .readyToCollect ? "开始采集" : "准备采集") {
                        onPrepareToCollect()
                    }
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
