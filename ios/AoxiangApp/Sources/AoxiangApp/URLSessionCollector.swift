import Foundation
import AoxiangCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(WebKit)
import WebKit
#endif

/// Applies browser-equivalent domain, path, HTTPS, and expiry boundaries
/// before a WebKit cookie can be copied into one in-memory URLSession request.
/// The helper neither persists nor logs cookie values.
enum AoxiangCookieScope {
    static func header(from cookies: [HTTPCookie], for url: URL, now: Date = Date()) -> String? {
        let values = cookies
            .filter { allows($0, for: url, now: now) }
            .sorted {
                if $0.path.count != $1.path.count { return $0.path.count > $1.path.count }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.value < $1.value
            }
            .map { "\($0.name)=\($0.value)" }
        return values.isEmpty ? nil : values.joined(separator: "; ")
    }

    static func allows(_ cookie: HTTPCookie, for url: URL, now: Date = Date()) -> Bool {
        guard !cookie.name.isEmpty,
              let host = url.host?.lowercased(),
              belongsToHost(cookie, host: host),
              matchesPath(cookie.path, requestPath: url.path),
              !(cookie.isSecure && url.scheme?.lowercased() != "https"),
              !(cookie.expiresDate.map { $0 <= now } ?? false) else {
            return false
        }
        return true
    }

    static func belongsToHost(_ cookie: HTTPCookie, host: String) -> Bool {
        !cookie.name.isEmpty && matchesDomain(cookie.domain, host: host.lowercased())
    }

    private static func matchesDomain(_ rawDomain: String, host: String) -> Bool {
        let domain = rawDomain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !domain.isEmpty else { return false }
        if rawDomain.hasPrefix(".") {
            return host == domain || host.hasSuffix(".\(domain)")
        }
        return host == domain
    }

    private static func matchesPath(_ rawCookiePath: String, requestPath: String) -> Bool {
        let cookiePath = rawCookiePath.isEmpty ? "/" : rawCookiePath
        let path = requestPath.isEmpty ? "/" : requestPath
        guard path.hasPrefix(cookiePath) else { return false }
        guard path != cookiePath, !cookiePath.hasSuffix("/") else { return true }
        let index = path.index(path.startIndex, offsetBy: cookiePath.count)
        return path[index] == "/"
    }
}

/// URLSession is intentionally a thin adapter. Callers must first obtain a
/// `.use(.urlSession)` decision from `ForegroundCollectionPlanner`; page-
/// JavaScript endpoints stay on the visible WebView path.
public final class URLSessionHTTPCollectionAdapter: StableHTTPCollectionPort {
    private let session: URLSession
    private let cookieHeaderProvider: ((URL) async -> String?)?

    public init(
        session: URLSession = .shared,
        cookieHeaderProvider: ((URL) async -> String?)? = nil
    ) {
        self.session = session
        self.cookieHeaderProvider = cookieHeaderProvider
    }

    public func send(_ request: StableHTTPCollectionRequest) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.timeoutInterval = request.timeoutInterval
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if urlRequest.value(forHTTPHeaderField: "Cookie") == nil,
           let cookieHeader = await cookieHeaderProvider?(request.url) {
            urlRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw CollectionTransportError.nonSuccessStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw CollectionTransportError.authenticationRequired
            }
            if http.statusCode == 429 {
                throw CollectionTransportError.retryable(.rateLimited)
            }
            if http.statusCode == 408 || (500...599).contains(http.statusCode) {
                throw CollectionTransportError.retryable(.serverUnavailable)
            }
            throw CollectionTransportError.nonSuccessStatus(http.statusCode)
        }
        return (data, http)
    }
}

#if canImport(WebKit)
public extension URLSessionHTTPCollectionAdapter {
    /// Uses the same WebKit cookie store as the visible login WebView. Cookie
    /// values are copied only into the in-memory request and are never logged,
    /// encoded into a backup, or written to a separate store.
    convenience init(
        session: URLSession = .shared,
        cookieStore: WKHTTPCookieStore
    ) {
        self.init(session: session, cookieHeaderProvider: { requestURL in
            await Self.cookieHeader(from: cookieStore, for: requestURL)
        })
    }

    private static func cookieHeader(from store: WKHTTPCookieStore, for url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: AoxiangCookieScope.header(from: cookies, for: url))
            }
        }
    }
}
#endif
