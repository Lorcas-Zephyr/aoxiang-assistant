import Foundation
import XCTest
@testable import AoxiangApp

final class URLSessionCollectorTests: XCTestCase {
    func testDefaultSessionConfigurationDoesNotUseAutomaticCookieStorage() {
        let configuration = URLSessionHTTPCollectionAdapter.defaultSessionConfiguration()

        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
    }
}
