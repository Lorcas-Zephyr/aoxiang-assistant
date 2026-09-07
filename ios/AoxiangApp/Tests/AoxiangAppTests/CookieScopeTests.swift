import Foundation
import XCTest
@testable import AoxiangApp

#if canImport(WebKit)
final class CookieScopeTests: XCTestCase {
    func testCookieHeaderIncludesOnlyCookiesAllowedForRequestURL() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let matching = try cookie(
            name: "session",
            value: "redacted-value",
            domain: ".example.edu",
            path: "/student"
        )
        let wrongDomain = try cookie(
            name: "other",
            value: "must-not-leak",
            domain: ".other.example",
            path: "/"
        )
        let wrongPath = try cookie(
            name: "admin",
            value: "must-not-leak",
            domain: ".example.edu",
            path: "/admin"
        )
        let secureOnHTTP = try cookie(
            name: "secure",
            value: "must-not-leak",
            domain: ".example.edu",
            path: "/",
            secure: true
        )
        let expired = try cookie(
            name: "expired",
            value: "must-not-leak",
            domain: ".example.edu",
            path: "/",
            expires: now.addingTimeInterval(-1)
        )

        let header = AoxiangCookieScope.header(
            from: [wrongDomain, wrongPath, secureOnHTTP, expired, matching],
            for: URL(string: "http://jwxt.example.edu/student/home")!,
            now: now
        )

        XCTAssertEqual(header, "session=redacted-value")
    }

    func testCookieHeaderDoesNotTreatAHostSuffixAsAValidDomain() throws {
        let cookie = try cookie(
            name: "session",
            value: "must-not-leak",
            domain: ".example.edu",
            path: "/"
        )

        let header = AoxiangCookieScope.header(
            from: [cookie],
            for: URL(string: "https://notexample.edu/")!,
            now: Date()
        )

        XCTAssertNil(header)
    }

    func testHostOnlyCookieDoesNotLeakToASubdomain() throws {
        let cookie = try cookie(
            name: "session",
            value: "must-not-leak",
            domain: "jwxt.example.edu",
            path: "/"
        )

        let header = AoxiangCookieScope.header(
            from: [cookie],
            for: URL(string: "https://child.jwxt.example.edu/")!,
            now: Date()
        )

        XCTAssertNil(header)
    }

    private func cookie(
        name: String,
        value: String,
        domain: String,
        path: String,
        secure: Bool = false,
        expires: Date? = nil
    ) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
        ]
        if secure { properties[.secure] = "TRUE" }
        if let expires { properties[.expires] = expires }
        guard let cookie = HTTPCookie(properties: properties) else {
            throw NSError(domain: "CookieScopeTests", code: 1)
        }
        return cookie
    }
}
#endif
