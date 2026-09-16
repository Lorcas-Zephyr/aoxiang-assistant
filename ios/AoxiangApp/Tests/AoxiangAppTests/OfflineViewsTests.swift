import Foundation
import XCTest

final class OfflineViewsTests: XCTestCase {
    func testRunningCollectionPresentsDedicatedCancellationControl() throws {
        let source = try offlineViewsSource()

        XCTAssertTrue(source.contains("if isCollecting {"))
        XCTAssertTrue(source.contains("Label(\"取消采集\", systemImage: \"xmark.circle.fill\")"))
        XCTAssertTrue(source.contains(".safeAreaInset(edge: .top"))
    }

    func testCancellationInvalidatesActiveTaskAndRestoresInteractiveState() throws {
        let source = try offlineViewsSource()
        let cancellationBody = try XCTUnwrap(
            source.components(separatedBy: "private func cancelCollection() {").dropFirst().first
                .flatMap { $0.components(separatedBy: "\n    private func collectionStatus").first }
        )

        XCTAssertTrue(cancellationBody.contains("pendingCollectionStart = false"))
        XCTAssertTrue(cancellationBody.contains("collectionTask?.cancel()"))
        XCTAssertTrue(cancellationBody.contains("activeCollectionID = nil"))
        XCTAssertTrue(cancellationBody.contains("isCollecting = false"))
        XCTAssertTrue(cancellationBody.contains("showingAuthentication = false"))
    }

    func testElectricityIssueIsConsumedWithoutDiscardingSuccessfulEducationData() throws {
        let source = try offlineViewsSource()

        XCTAssertTrue(source.contains("if let electricityIssue = result.electricityIssue"))
        XCTAssertTrue(source.contains("handleElectricityIssue(electricityIssue)"))
        XCTAssertTrue(source.contains("showingAuthentication = false"))
        XCTAssertTrue(source.contains("if result.electricityIssue == nil"))
        XCTAssertTrue(source.contains("result.grades"))
        XCTAssertTrue(source.contains("result.schedule"))
    }

    func testAuthenticationAndRetryableElectricityIssuesUpdateAuthenticationState() throws {
        let source = try offlineViewsSource()
        let helper = try XCTUnwrap(
            source.components(separatedBy: "private func handleElectricityIssue(").dropFirst().first
                .flatMap { $0.components(separatedBy: "\n    private func collectionStatus").first }
        )

        XCTAssertTrue(helper.contains("case .needsLogin:"))
        XCTAssertTrue(helper.contains("case .needsSMS:"))
        XCTAssertTrue(helper.contains("case .retryable(let reason):"))
        XCTAssertTrue(helper.contains("authenticationModel.recordCollectionFailure(.authenticationRequired)"))
        XCTAssertTrue(helper.contains("authenticationModel.recordCollectionFailure(.smsRequired)"))
        XCTAssertTrue(helper.contains("authenticationModel.recordCollectionFailure(.retryable(reason))"))
    }

    func testNonAuthenticationElectricityIssuesShowRetryableMessageWithoutChangingAuthState() throws {
        let source = try offlineViewsSource()
        let helper = try XCTUnwrap(
            source.components(separatedBy: "private func handleElectricityIssue(").dropFirst().first
                .flatMap { $0.components(separatedBy: "\n    private func collectionStatus").first }
        )

        XCTAssertTrue(helper.contains("case .invalidResponse(let message):"))
        XCTAssertTrue(helper.contains("case .settlement:"))
        XCTAssertTrue(helper.contains("电费读取失败"))
        XCTAssertTrue(helper.contains("请稍后重试"))
        XCTAssertFalse(helper.contains("recordCollectionFailure(.invalidResponse"))
        XCTAssertFalse(helper.contains("recordCollectionFailure(.settlement"))
    }

    func testElectricityRetryEntryPointRemainsAvailableAfterPartialSuccess() throws {
        let source = try offlineViewsSource()

        XCTAssertTrue(source.contains("电费读取失败，可重试"))
        XCTAssertTrue(source.contains("Button(\"重试电费\")"))
        XCTAssertTrue(source.contains("requestCollection()"))
        XCTAssertTrue(source.contains("showingAuthentication = true"))
    }

    private func offlineViewsSource() throws -> String {
        let appRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: appRoot.appendingPathComponent("Sources/AoxiangApp/OfflineViews.swift"),
            encoding: .utf8
        )
    }
}
