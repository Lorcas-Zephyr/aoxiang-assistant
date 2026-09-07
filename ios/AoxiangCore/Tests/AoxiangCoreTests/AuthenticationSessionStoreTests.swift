import XCTest
@testable import AoxiangCore

final class AuthenticationSessionStoreTests: XCTestCase {
    func testStoreStartsAtNeedsLoginAndContainsNoSecretFields() throws {
        let store = AuthenticationSessionStore()

        XCTAssertEqual(store.state, .needsLogin)
        let encoded = try JSONEncoder().encode(store.state)
        let text = String(decoding: encoded, as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("password"))
        XCTAssertFalse(text.contains("cookie"))
        XCTAssertFalse(text.contains("token"))
    }

    func testStorePublishesOnlyTheLatestState() {
        let store = AuthenticationSessionStore()
        store.set(.authenticated)
        XCTAssertEqual(store.state, .authenticated)

        store.set(.readyToCollect)
        XCTAssertEqual(store.state, .readyToCollect)
    }
}
