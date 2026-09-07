import XCTest
@testable import AoxiangCore

final class CollectionPolicyTests: XCTestCase {
    func testStableHTTPUsesURLSessionOnlyAfterAuthentication() {
        let planner = ForegroundCollectionPlanner()
        XCTAssertEqual(
            planner.plan(state: .readyToCollect, capability: .stableHTTP),
            .use(.urlSession)
        )
        XCTAssertEqual(
            planner.plan(state: .needsLogin, capability: .stableHTTP),
            .needsLogin
        )
    }

    func testPageJavaScriptRequiresVisibleWebView() {
        let planner = ForegroundCollectionPlanner()
        XCTAssertEqual(
            planner.plan(state: .authenticated, capability: .pageJavaScript),
            .blocked(.collectionNotReady)
        )
    }

    func testSmsAndAttentionNeverBecomeCollectionTransport() {
        let planner = ForegroundCollectionPlanner()
        XCTAssertEqual(
            planner.plan(state: .needsSMS, capability: .stableHTTP),
            .needsSMS
        )
        XCTAssertEqual(
            planner.plan(
                state: .needsUserAttention(reason: .authenticationExpired),
                capability: .pageJavaScript
            ),
            .blocked(.authenticationExpired)
        )
    }
}
