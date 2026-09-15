#if os(iOS) && canImport(WebKit)
import Foundation
import XCTest
import WebKit
import AoxiangCore
@testable import AoxiangApp

@MainActor
final class VisibleAuthenticationWebViewTests: XCTestCase {
    private let loginURL = URL(string: "https://jwxt.nwpu.edu.cn/student/sso-login")!

    func testCancellingElectricityCollectionFinishesTheContinuation() async {
        await assertCollectionCancellation { model in
            _ = try await model.collectElectricityBalance()
        }
    }

    func testCancellingPortraitCollectionFinishesTheContinuation() async {
        await assertCollectionCancellation { model in
            _ = try await model.collectPortraitHTML()
        }
    }

    func testCancellingEducationCollectionFinishesTheContinuation() async {
        await assertCollectionCancellation { model in
            _ = try await model.collectEducationData()
        }
    }

    func testEducationNavigationFailureIsRecordedAsCollectionRetryableFailure() async throws {
        let model = makeReadyModel()
        let task = Task { @MainActor in
            try await model.collectEducationData()
        }
        await yieldToCollectionStart()

        model.webView(
            model.webView,
            didFail: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        )

        do {
            _ = try await task.value
            XCTFail("expected collection navigation failure")
        } catch let failure as PortalCollectionFailure {
            XCTAssertEqual(failure, .retryable(.networkUnavailable))
        }
        assertCollectionRetryableState(model)
    }

    func testProvisionalEducationNavigationFailureIsRecordedAsCollectionRetryableFailure() async throws {
        let model = makeReadyModel()
        let task = Task { @MainActor in
            try await model.collectEducationData()
        }
        await yieldToCollectionStart()

        model.webView(
            model.webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        )

        do {
            _ = try await task.value
            XCTFail("expected provisional collection navigation failure")
        } catch let failure as PortalCollectionFailure {
            XCTAssertEqual(failure, .retryable(.networkUnavailable))
        }
        assertCollectionRetryableState(model)
    }

    private func assertCollectionCancellation(
        _ operation: @escaping @MainActor (VisibleAuthenticationViewModel) async throws -> Void
    ) async {
        let model = makeReadyModel()
        let finished = expectation(description: "cancelled collection finishes")
        let task = Task { @MainActor in
            do {
                try await operation(model)
                XCTFail("expected collection cancellation")
            } catch let failure as PortalCollectionFailure {
                XCTAssertEqual(failure, .cancelled)
                finished.fulfill()
            } catch {
                XCTFail("unexpected collection error: \(error)")
            }
        }
        await yieldToCollectionStart()
        task.cancel()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(model.state, .readyToCollect)
    }

    private func makeReadyModel() -> VisibleAuthenticationViewModel {
        VisibleAuthenticationViewModel(
            loginURL: loginURL,
            successRule: .jwxtStudentHome,
            sessionStore: AuthenticationSessionStore(initialState: .readyToCollect)
        )
    }

    private func yieldToCollectionStart() async {
        for _ in 0..<4 {
            await Task.yield()
        }
    }

    private func assertCollectionRetryableState(_ model: VisibleAuthenticationViewModel) {
        guard case .retryableFailure(let failure) = model.state else {
            return XCTFail("expected retryable collection state, got \(model.state)")
        }
        XCTAssertEqual(failure.operation, .collection)
        XCTAssertEqual(failure.reason, .networkUnavailable)
    }
}
#endif
