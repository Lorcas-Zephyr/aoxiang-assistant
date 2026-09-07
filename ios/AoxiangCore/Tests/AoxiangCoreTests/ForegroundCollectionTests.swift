import Foundation
import XCTest
@testable import AoxiangCore

final class ForegroundCollectionTests: XCTestCase {
    func testPolicyKeepsJavaScriptCollectionOnVisiblePath() {
        XCTAssertEqual(
            CollectionPolicy.decide(state: .readyToCollect, capability: .pageJavaScript),
            .use(.visibleWebView)
        )
    }

    func testPolicyBlocksHTTPBeforeAuthentication() {
        XCTAssertEqual(
            CollectionPolicy.decide(state: .needsLogin, capability: .stableHTTP),
            .needsLogin
        )
    }
}
