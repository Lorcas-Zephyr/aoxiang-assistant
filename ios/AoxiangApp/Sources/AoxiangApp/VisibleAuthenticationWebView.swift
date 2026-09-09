import Foundation
import AoxiangCore

#if canImport(WebKit)
import WebKit
#endif

public enum VisibleCollectionTarget: Equatable {
    case education
    case portrait
    case electricity
}

/// Classifies navigation destinations without reading page state or cookie
/// values. The electricity portal deliberately starts through one CAS-shaped
/// URL, so that expected first hop must not be mistaken for session expiry.
public struct VisibleCollectionNavigationPolicy {
    public static let electricityCASBootstrapURL = URL(
        string: "https://yktapp.nwpu.edu.cn/berserker-auth/cas/login/supwisdom?targetUrl=https%3A%2F%2Fyktapp.nwpu.edu.cn%2Fplat"
    )!

    public init() {}

    public func isAuthenticationRedirect(
        _ url: URL?,
        target: VisibleCollectionTarget,
        allowsExpectedElectricityCASBootstrap: Bool
    ) -> Bool {
        if target == .electricity,
           allowsExpectedElectricityCASBootstrap,
           isExpectedElectricityCASBootstrap(url) {
            return false
        }
        guard let url else { return false }
        let path = url.path.lowercased()
        let text = url.absoluteString.lowercased()
        return text.contains("/cas/login")
            || text.contains("/sso/login")
            || path.contains("login")
            || path.contains("auth")
            || path.contains("error")
            || path.contains("unauthorized")
            || path.contains("forbidden")
    }

    public func isExpectedElectricityCASBootstrap(_ url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "yktapp.nwpu.edu.cn",
              url.path.lowercased() == "/berserker-auth/cas/login/supwisdom",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let targetURLText = components.queryItems?.first(where: { $0.name == "targetUrl" })?.value,
              let targetURL = URL(string: targetURLText),
              targetURL.scheme?.lowercased() == "https",
              targetURL.host?.lowercased() == "yktapp.nwpu.edu.cn",
              targetURL.path.lowercased() == "/plat" else {
            return false
        }
        return true
    }
}

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
    private var electricityPollTask: Task<Void, Never>?
    private var electricityEvaluationInFlight = false
    private var electricityCASBootstrapPending = false
    private var portraitContinuation: CheckedContinuation<String?, Error>?
    private var portraitTimeoutTask: Task<Void, Never>?
    private var educationContinuation: CheckedContinuation<PortalVisibleEducationData, Error>?
    private var educationTimeoutTask: Task<Void, Never>?
    private var educationEvaluationInFlight = false
    private let studentGradeURL = URL(string: "https://jwxt.nwpu.edu.cn/student/for-std/grade/sheet/")!
    private let studentPortraitURL = URL(string: "https://jwxt.nwpu.edu.cn/student/for-std/student-portrait")!
    private let electricityLoginURL = VisibleCollectionNavigationPolicy.electricityCASBootstrapURL
    private let navigationPolicy = VisibleCollectionNavigationPolicy()

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

    /// Re-opens the collection gate after a transient collection failure.
    /// The existing WebView and cookie store are retained; credentials never
    /// cross this boundary.
    @discardableResult
    public func retryCollection() -> Bool {
        guard case .retryableFailure(let failure) = state,
              failure.operation == .collection else { return false }
        do {
            state = try machine.handle(.retry)
            sessionStore.set(state)
            lastError = nil
            return state == .readyToCollect
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public var canRetryCollection: Bool {
        guard case .retryableFailure(let failure) = state else { return false }
        return failure.operation == .collection
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
            electricityCASBootstrapPending = true
            electricityPollTask?.cancel()
            electricityPollTask = nil
            electricityEvaluationInFlight = false
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

    /// Collects education data inside the authenticated WebView. The script
    /// uses same-origin fetch with the browser's own cookies and returns only
    /// the sanitized fields accepted by `PortalCollectionParsers`.
    public func collectEducationData() async throws -> PortalVisibleEducationData {
        guard state == .readyToCollect else {
            throw PortalCollectionFailure.invalidResponse("collection not prepared")
        }
        guard electricityContinuation == nil, portraitContinuation == nil,
              educationContinuation == nil else {
            throw PortalCollectionFailure.retryable(.invalidResponse)
        }
        return try await withCheckedThrowingContinuation { continuation in
            educationContinuation = continuation
            educationEvaluationInFlight = false
            educationTimeoutTask?.cancel()
            educationTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.finishEducation(.failure(PortalCollectionFailure.retryable(.serverUnavailable)))
                }
            }
            webView.load(URLRequest(url: studentGradeURL))
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
        if educationContinuation != nil,
           navigationPolicy.isAuthenticationRedirect(
               webView.url,
               target: .education,
               allowsExpectedElectricityCASBootstrap: false
           ) {
            finishEducation(.failure(PortalCollectionFailure.authenticationRequired))
            return
        }
        if electricityContinuation != nil,
           navigationPolicy.isAuthenticationRedirect(
               webView.url,
               target: .electricity,
               allowsExpectedElectricityCASBootstrap: electricityCASBootstrapPending
           ) {
            finishElectricity(.failure(PortalCollectionFailure.authenticationRequired))
            return
        }
        if electricityContinuation != nil,
           navigationPolicy.isExpectedElectricityCASBootstrap(webView.url) {
            electricityCASBootstrapPending = false
        }
        if portraitContinuation != nil,
           navigationPolicy.isAuthenticationRedirect(
               webView.url,
               target: .portrait,
               allowsExpectedElectricityCASBootstrap: false
           ) {
            finishPortrait(.failure(PortalCollectionFailure.authenticationRequired))
            return
        }
        handleEducationNavigation(in: webView)
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
        if educationContinuation != nil {
            finishEducation(.failure(PortalCollectionFailure.retryable(.networkUnavailable)))
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
        if educationContinuation != nil {
            finishEducation(.failure(PortalCollectionFailure.retryable(.networkUnavailable)))
        }
    }

    private func handleEducationNavigation(in webView: WKWebView) {
        guard educationContinuation != nil,
              !educationEvaluationInFlight,
              let url = webView.url,
              url.host?.lowercased() == studentGradeURL.host?.lowercased(),
              isEducationCollectionPage(url.path) else { return }
        educationEvaluationInFlight = true
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                // Xcode 26 imports this iOS 15 API as async throws; there is
                // no completion-handler overload in the current SDK.
                let value = try await webView.callAsyncJavaScript(
                    Self.educationCollectionScript,
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                )
                guard self.educationContinuation != nil else { return }
                self.educationEvaluationInFlight = false
                guard let json = value as? String,
                      let data = json.data(using: .utf8) else {
                    self.finishEducation(.failure(PortalCollectionFailure.invalidResponse("visible education payload unavailable")))
                    return
                }
                do {
                    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    switch root?["phase"] as? String {
                    case "needs_login":
                        self.finishEducation(.failure(PortalCollectionFailure.authenticationRequired))
                    case "needs_sms":
                        self.finishEducation(.failure(PortalCollectionFailure.smsRequired))
                    case "retryable":
                        self.finishEducation(.failure(PortalCollectionFailure.retryable(.serverUnavailable)))
                    default:
                        self.finishEducation(.success(try PortalCollectionParsers.parseVisibleEducation(data)))
                    }
                } catch let failure as PortalCollectionFailure {
                    self.finishEducation(.failure(failure))
                } catch {
                    self.finishEducation(.failure(PortalCollectionFailure.invalidResponse("visible education payload malformed")))
                }
            } catch {
                guard self.educationContinuation != nil else { return }
                self.educationEvaluationInFlight = false
                self.finishEducation(.failure(PortalCollectionFailure.retryable(.serverUnavailable)))
            }
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
        guard electricityContinuation != nil, !electricityEvaluationInFlight, let url = webView.url,
              url.host?.lowercased() == "yktapp.nwpu.edu.cn" else { return }
        let path = url.path.lowercased()
        if path.hasPrefix("/plat") {
            electricityEvaluationInFlight = true
            webView.evaluateJavaScript("""
            (() => {
              const token = new URL(location.href).searchParams.get('synjones-auth') || sessionStorage.getItem('access_token') || '';
              if (!token) return false;
              location.replace(location.origin + '/jfdt/charge/feeitem/toAppitem?feeitemid=182&synjones-auth=' + encodeURIComponent(token) + '&appId=36&loginFrom=h5&type=app');
              return true;
            })()
            """) { [weak self] value, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.electricityEvaluationInFlight = false
                    if let error {
                        self.finishElectricity(.failure(PortalCollectionFailure.retryable(.serverUnavailable)))
                        self.lastError = error.localizedDescription
                    } else if (value as? NSNumber)?.boolValue != true {
                        self.scheduleElectricityEvaluation()
                    }
                }
            }
            return
        }
        guard path.hasPrefix("/jfdt/") else { return }
        electricityEvaluationInFlight = true
        let script = Self.electricityBalanceScript
        webView.evaluateJavaScript(script) { [weak self] value, error in
            Task { @MainActor in
                guard let self else { return }
                self.electricityEvaluationInFlight = false
                if let error {
                    self.finishElectricity(.failure(PortalCollectionFailure.retryable(.serverUnavailable)))
                    self.lastError = error.localizedDescription
                    return
                }
                if let number = value as? NSNumber {
                    self.finishElectricity(.success(number.doubleValue))
                } else {
                    self.scheduleElectricityEvaluation()
                }
            }
        }
    }

    private func scheduleElectricityEvaluation() {
        guard electricityContinuation != nil, electricityPollTask == nil else { return }
        electricityPollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.electricityContinuation != nil else { return }
                self.electricityPollTask = nil
                self.handleElectricityNavigation(in: self.webView)
            }
        }
    }

    private func finishElectricity(_ result: Result<Double, Error>) {
        electricityTimeoutTask?.cancel()
        electricityTimeoutTask = nil
        electricityPollTask?.cancel()
        electricityPollTask = nil
        electricityEvaluationInFlight = false
        electricityCASBootstrapPending = false
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

    private func finishEducation(_ result: Result<PortalVisibleEducationData, Error>) {
        educationTimeoutTask?.cancel()
        educationTimeoutTask = nil
        educationEvaluationInFlight = false
        guard let continuation = educationContinuation else { return }
        educationContinuation = nil
        continuation.resume(with: result)
    }

    private static let electricityBalanceScript = """
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
            for (const [label, candidate] of Object.entries(value)) {
              if (!/(?:剩余.*(?:电费|金额|电量)|(?:电费|电量).*余额)/.test(String(label))) continue;
              const parsed = parse(candidate);
              if (parsed !== null) return parsed;
            }
            return null;
          };
          const app = document.querySelector('#app');
          const root = app && (app.__vue__ ||
            (app.__vueParentComponent && app.__vueParentComponent.proxy) ||
            (app.__vue_app__ && app.__vue_app__._instance && app.__vue_app__._instance.proxy));
          const queue = root ? [root] : [];
          const seen = new Set();
          while (queue.length && seen.size < 100) {
            const component = queue.shift();
            if (!component || seen.has(component)) continue;
            seen.add(component);
            const data = component.$data || {};
            const candidates = [
              component.aboutEleric && component.aboutEleric.electricInfo,
              data.aboutEleric && data.aboutEleric.electricInfo,
              component.aboutElectric && component.aboutElectric.electricInfo,
              data.aboutElectric && data.aboutElectric.electricInfo,
              component.electricInfo,
              data.electricInfo
            ];
            for (const candidate of candidates) {
              const parsed = inspect(candidate);
              if (parsed !== null) return parsed;
            }
            (component.$children || []).forEach(child => queue.push(child));
          }
          const text = document.body ? document.body.innerText : '';
          const direct = text.match(/(?:当前剩余电量|剩余电量|电量余额)\\s*[：:]\\s*(-?\\d+(?:\\.\\d+)?)/) ||
            text.match(/(?:剩余电费|电费余额|剩余金额)\\s*[：:]?\\s*(?:¥|￥)?\\s*(-?\\d+(?:\\.\\d+)?)\\s*元/) ||
            text.match(/(?:¥|￥)?\\s*(-?\\d+(?:\\.\\d+)?)\\s*(?:元|度)\\s*[：:]?\\s*(?:剩余电费|电费余额|剩余金额|当前剩余电量|剩余电量|电量余额)/);
          return direct ? parse(direct[1]) : null;
        })()
        """

    private static let educationCollectionScript = #"""
    return (async () => {
      const timeoutMs = 12000;
      const timed = async (url, options) => {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeoutMs);
        try {
          return await fetch(url, Object.assign({}, options || {}, {
            credentials: 'include', cache: 'no-store', signal: controller.signal
          }));
        } finally { clearTimeout(timer); }
      };
      const text = async (url) => {
        const response = await timed(url);
        const body = await response.text();
        if (response.status === 401 || response.status === 403) return { __auth: true, body };
        if (!response.ok) throw new Error('HTTP ' + response.status);
        return body;
      };
      const json = async (url) => {
        const response = await timed(url, { headers: { Accept: 'application/json' } });
        const body = await response.text();
        if (response.status === 401 || response.status === 403) return { __auth: true };
        if (!response.ok) throw new Error('HTTP ' + response.status);
        try { return JSON.parse(body); } catch (_) { return { __html: body }; }
      };
      const clean = value => String(value == null ? '' : value).trim();
      const studentID = html => {
        const input = document.querySelector('#studentId');
        const liveValue = clean(window.studentId || (input && input.value) || '');
        if (liveValue) return liveValue;
        const match = String(html || '').match(/id=["']studentId["'][^>]*value=["']([^"']+)["']/i) ||
          String(html || '').match(/value=["']([^"']+)["'][^>]*id=["']studentId["']/i) ||
          String(html || '').match(/(?:studentId|studentAssoc)\s*[=:]\s*["']([^"']+)["']/i);
        return match ? clean(match[1]) : '';
      };
      const scheduleStudentId = () => {
        try {
          const resources = performance.getEntriesByType('resource').slice().reverse();
          for (const entry of resources) {
            const match = String(entry && entry.name || '').match(
              /\/for-std\/course-table\/semester\/[^/]+\/print-data\/([^/?#]+)/
            );
            if (match && match[1]) return decodeURIComponent(match[1]);
          }
        } catch (_) {}
        return '';
      };
      const parseSemesterValue = raw => {
        if (Array.isArray(raw)) return raw;
        if (raw && typeof raw === 'object') return Object.values(raw);
        if (typeof raw !== 'string') return [];
        try {
          const parsed = JSON.parse(raw);
          if (Array.isArray(parsed)) return parsed;
          return parsed && typeof parsed === 'object' ? Object.values(parsed) : [];
        } catch (_) { return []; }
      };
      const semesterID = term => clean(term && (term.id || term.code || term.dataSemester || term.value));
      const normalizeSemester = term => {
        if (!term || typeof term !== 'object') return null;
        const id = semesterID(term);
        return id ? Object.assign({}, term, { id }) : null;
      };
      const semesters = html => {
        const globals = [window.semesters, window.semesterList, window.semesterOptions, window.__SEMESTERS__];
        for (const globalValue of globals) {
          const parsed = parseSemesterValue(globalValue).map(normalizeSemester).filter(Boolean);
          if (parsed.length) return parsed;
        }
        const source = String(html || '');
        const jsonParseMatch = source.match(/(?:var|const|let)\s+semesters\s*=\s*JSON\.parse\(\s*(['"])([\s\S]*?)\1\s*\)/);
        if (jsonParseMatch) {
          const raw = jsonParseMatch[2].replace(/\\'/g, "'").replace(/\\\"/g, '\"');
          const parsed = parseSemesterValue(raw).map(normalizeSemester).filter(Boolean);
          if (parsed.length) return parsed;
        }
        const directMatch = source.match(/(?:var|const|let)\s+semesters\s*=\s*(\[[\s\S]*?\])\s*;/);
        if (directMatch) {
          const parsed = parseSemesterValue(directMatch[1]).map(normalizeSemester).filter(Boolean);
          if (parsed.length) return parsed;
        }
        const embedded = document.querySelector('script[type="application/json"][data-semesters], #semesters');
        return parseSemesterValue(embedded && (embedded.textContent || embedded.value))
          .map(normalizeSemester).filter(Boolean);
      };
      const authenticationPhase = value => {
        const body = String(value || '').toLowerCase();
        if (body.includes('短信') || body.includes('sms') || body.includes('动态验证码')) return 'needs_sms';
        if (body.includes('统一身份认证') || body.includes('统一认证') ||
          body.includes('cas/login') || body.includes('请输入账号') ||
          body.includes('请输入密码') || body.includes('登录信息已失效') ||
          body.includes('会话已失效')) return 'needs_login';
        return '';
      };
      const teacherValues = value => {
        if (Array.isArray(value)) return value.flatMap(teacherValues);
        if (value && typeof value === 'object') {
          for (const key of ['nameZh', 'name', 'teacherName', 'teacher_name', 'teacher']) {
            const values = teacherValues(value[key]);
            if (values.length) return values;
          }
          return [];
        }
        const text = clean(value);
        return text ? text.split(/[、\/,，]/).map(clean).filter(Boolean) : [];
      };
      try {
        const sheetValue = await text('/student/for-std/grade/sheet/');
        if (sheetValue && sheetValue.__auth) return JSON.stringify({ phase: 'needs_login' });
        const sheet = String(sheetValue || '');
        const sheetAuth = authenticationPhase(sheet);
        if (sheetAuth) return JSON.stringify({ phase: sheetAuth });
        let id = studentID(sheet) || scheduleStudentId();
        let terms = semesters(sheet);
        if (!id) {
          const info = await json('/student/for-std/student-portrait/getStdInfo');
          if (info && info.__auth) return JSON.stringify({ phase: 'needs_login' });
          if (info && info.__html) {
            const phase = authenticationPhase(info.__html);
            return JSON.stringify({ phase: phase || 'retryable' });
          }
          id = clean(info && info.student && (info.student.id || info.student.studentId) ||
            info && (info.studentId || info.studentAssoc) ||
            info && info.data && (info.data.id || info.data.studentId) || '');
        }
        if (!id || !terms.length) return JSON.stringify({ phase: 'retryable' });
        const responses = [];
        let batchAuthenticationPhase = '';
        for (let offset = 0; offset < terms.length; offset += 4) {
          const batch = terms.slice(offset, offset + 4);
          const values = await Promise.all(batch.map(async term => {
            try {
              const value = await json('/student/for-std/grade/sheet/info/' + encodeURIComponent(id) + '?semester=' + encodeURIComponent(semesterID(term)));
              if (value && value.__auth) {
                batchAuthenticationPhase = 'needs_login';
                return null;
              }
              if (value && value.__html) {
                const phase = authenticationPhase(value.__html);
                if (phase) {
                  batchAuthenticationPhase = phase;
                  return null;
                }
              }
              return value;
            } catch (_) { return null; }
          }));
          values.filter(Boolean).forEach(value => responses.push(value));
          if (batchAuthenticationPhase) return JSON.stringify({ phase: batchAuthenticationPhase });
        }
        const responsePhase = responses.find(value => value && value.__phase);
        if (responsePhase) return JSON.stringify({ phase: responsePhase.__phase });
        if (!responses.length) return JSON.stringify({ phase: 'retryable' });
        const grades = [];
        responses.forEach(response => {
          const map = response && response.semesterId2studentGrades || {};
          Object.keys(map).forEach(termID => (Array.isArray(map[termID]) ? map[termID] : []).forEach(row => {
            if (row && row.published === false) return;
            const course = row && row.course || {};
            const name = clean(course.nameZh || course.lessonNameZh || row && row.lessonNameZh);
            if (!name) return;
            grades.push({ course: name, credits: Number(course.credits || row.credits || 0), point: row.gp == null ? null : Number(row.gp), score: row.gaGrade == null ? null : Number(row.gaGrade), category: clean(row.category || '课程'), detail: clean(row.gradeDetail || '') });
          }));
        });
        let gpa = null;
        try { const value = await json('/student/for-std/student-portrait/getMyGpa?studentAssoc=' + encodeURIComponent(id)); gpa = value && !value.__auth ? value : null; } catch (_) {}
        const tableValue = await text('/student/for-std/course-table');
        if (tableValue && tableValue.__auth) return JSON.stringify({ phase: 'needs_login' });
        const tableHTML = String(tableValue || '');
        const tableAuth = authenticationPhase(tableHTML);
        if (tableAuth) return JSON.stringify({ phase: tableAuth });
        const tableTerms = semesters(tableHTML);
        if (!tableTerms.length) return JSON.stringify({ phase: 'retryable' });
        const businessToday = () => {
          try {
            const parts = new Intl.DateTimeFormat('en-US', {
              timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit'
            }).formatToParts(new Date());
            const values = Object.fromEntries(parts.filter(part => part.type !== 'literal').map(part => [part.type, part.value]));
            return values.year + '-' + values.month + '-' + values.day;
          } catch (_) {
            return new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
          }
        };
        const today = businessToday();
        const ordered = tableTerms.filter(term => term && semesterID(term) && /^\d{4}-\d{2}-\d{2}$/.test(String(term.startDate || ''))).sort((a, b) => String(a.startDate).localeCompare(String(b.startDate)));
        let index = ordered.findIndex(term => String(term.startDate) <= today && (!term.endDate || String(term.endDate) >= today));
        if (index < 0) { index = ordered.findIndex(term => String(term.startDate) > today); if (index < 0) index = ordered.length - 1; }
        if (!ordered.length) return JSON.stringify({ phase: 'retryable' });
        const effectiveEnd = (semester, print) => {
          const start = String(semester && semester.startDate || '');
          if (!/^\d{4}-\d{2}-\d{2}$/.test(start)) return '';
          const activities = print && print.studentTableVm && Array.isArray(print.studentTableVm.activities) ? print.studentTableVm.activities : [];
          const date = new Date(start + 'T00:00:00Z');
          let offset = 13;
          activities.forEach(activity => {
            const day = Number(activity && activity.weekday);
            (Array.isArray(activity && activity.weekIndexes) ? activity.weekIndexes : []).forEach(week => {
              const index = Number(week);
              if (Number.isFinite(index) && index > 0 && day >= 1 && day <= 7) offset = Math.max(offset, (index - 1) * 7 + day - 1);
            });
          });
          date.setUTCDate(date.getUTCDate() + offset);
          return date.toISOString().slice(0, 10);
        };
        let semester = ordered[index];
        let print = null;
        while (true) {
          const target = ordered[index];
          semester = target;
          try {
            const value = await json('/student/ws/semester/get/' + encodeURIComponent(semesterID(target)));
            if (value && value.__auth) return JSON.stringify({ phase: 'needs_login' });
            if (value && !value.__html) semester = value;
          } catch (_) {}
          print = await json('/student/for-std/course-table/semester/' + encodeURIComponent(semesterID(target)) + '/print-data/' + encodeURIComponent(id));
          if (print && print.__auth) return JSON.stringify({ phase: 'needs_login' });
          if (print && print.__html) {
            const phase = authenticationPhase(print.__html);
            return JSON.stringify({ phase: phase || 'retryable' });
          }
          const last = effectiveEnd(semester, print);
          if (!last || today <= last || index >= ordered.length - 1) break;
          index += 1;
        }
        const activities = print && print.studentTableVm && Array.isArray(print.studentTableVm.activities) ? print.studentTableVm.activities : [];
        const sanitized = activities.map(activity => ({ name: clean(activity.courseName), code: clean(activity.courseCode), credits: Number(activity.credits || 0), weekday: Number(activity.weekday || 0), startUnit: Number(activity.startUnit || 0), endUnit: Number(activity.endUnit || 0), weekIndexes: Array.isArray(activity.weekIndexes) ? activity.weekIndexes.map(Number).filter(Number.isFinite) : [], teachers: teacherValues(activity.teachers), campus: clean(activity.campus), building: clean(activity.building), room: clean(activity.room) })).filter(activity => activity.name);
        return JSON.stringify({ phase: 'success', grades, gpa, schedule: { semester, activities: sanitized } });
      } catch (_) { return JSON.stringify({ phase: 'retryable' }); }
    })()
    """#

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

    private func isEducationCollectionPage(_ path: String) -> Bool {
        let normalized = path.lowercased()
        return normalized == "/student/home"
            || normalized.hasPrefix("/student/for-std/grade/sheet")
            || normalized.hasPrefix("/student/for-std/course-table")
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
    private let isCollecting: Bool
    private let collectionStatus: String?

    public init(
        model: VisibleAuthenticationViewModel,
        onPrepareToCollect: (() -> Void)? = nil,
        isCollecting: Bool = false,
        collectionStatus: String? = nil
    ) {
        self.model = model
        self.onPrepareToCollect = onPrepareToCollect ?? {
            if model.canRetryCollection {
                _ = model.retryCollection()
            } else {
                model.prepareToCollect()
            }
        }
        self.isCollecting = isCollecting
        self.collectionStatus = collectionStatus
    }

    public var body: some View {
        VStack(spacing: 0) {
            VisibleAuthenticationWebView(model: model)
            if let collectionStatus {
                Text(collectionStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
            }
            HStack {
                Text(statusText).font(.caption)
                Spacer()
                if model.state == .authenticated || model.state == .readyToCollect {
                    Button(isCollecting ? "正在采集" : (model.state == .readyToCollect ? "开始采集" : "准备采集")) {
                        onPrepareToCollect()
                    }
                    .disabled(isCollecting)
                } else if model.canRetryCollection {
                    Button(isCollecting ? "正在采集" : "重试采集") {
                        onPrepareToCollect()
                    }
                    .disabled(isCollecting)
                }
                Button("重新登录") { model.startInteractiveLogin() }
                    .disabled(isCollecting)
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
