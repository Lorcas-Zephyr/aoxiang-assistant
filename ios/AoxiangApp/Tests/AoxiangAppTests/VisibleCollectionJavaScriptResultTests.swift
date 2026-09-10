import Foundation
import XCTest
@testable import AoxiangApp

final class VisibleCollectionJavaScriptResultTests: XCTestCase {
    func testJSONDataAcceptsStringAndFoundationStringBridgeValues() throws {
        let json = #"{"phase":"success","grades":[]}"#

        XCTAssertEqual(
            VisibleCollectionJavaScriptResult.jsonData(from: json),
            Data(json.utf8)
        )
        XCTAssertEqual(
            VisibleCollectionJavaScriptResult.jsonData(from: json as NSString),
            Data(json.utf8)
        )
    }

    func testJSONDataAcceptsAlreadyBridgedDictionary() throws {
        let value: [String: Any] = [
            "phase": "success",
            "grades": [["course": "数据结构", "credits": 3]],
        ]

        let data = try XCTUnwrap(VisibleCollectionJavaScriptResult.jsonData(from: value))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["phase"] as? String, "success")
        XCTAssertEqual((object["grades"] as? [[String: Any]])?.first?["course"] as? String, "数据结构")
    }

    func testJSONDataAcceptsObjectiveCCollectionBridgeValues() throws {
        let value = NSDictionary(dictionary: [
            "phase": "success",
            "grades": NSArray(array: [["course": "英语", "credits": 2]]),
        ])

        let data = try XCTUnwrap(VisibleCollectionJavaScriptResult.jsonData(from: value))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["phase"] as? String, "success")
        XCTAssertEqual((object["grades"] as? [[String: Any]])?.first?["course"] as? String, "英语")
    }

    func testJSONDataRejectsNullAndNonJSONValues() {
        XCTAssertNil(VisibleCollectionJavaScriptResult.jsonData(from: NSNull()))
        XCTAssertNil(VisibleCollectionJavaScriptResult.jsonData(from: NSObject()))
    }
}
