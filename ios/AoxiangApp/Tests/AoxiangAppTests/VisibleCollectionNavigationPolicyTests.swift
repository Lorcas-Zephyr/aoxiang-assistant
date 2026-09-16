import XCTest
@testable import AoxiangApp

final class VisibleCollectionNavigationPolicyTests: XCTestCase {
    func testExpectedElectricityCASBootstrapIsNotTreatedAsExpiredAuthentication() {
        let policy = VisibleCollectionNavigationPolicy()
        let bootstrap = URL(string: "https://yktapp.nwpu.edu.cn/berserker-auth/cas/login/supwisdom?targetUrl=https%3A%2F%2Fyktapp.nwpu.edu.cn%2Fplat")!

        XCTAssertFalse(
            policy.isAuthenticationRedirect(
                bootstrap,
                target: .electricity,
                allowsExpectedElectricityCASBootstrap: true
            )
        )
    }

    func testSameElectricityCASURLIsAuthenticationRedirectAfterBootstrapWasConsumed() {
        let policy = VisibleCollectionNavigationPolicy()
        let bootstrap = URL(string: "https://yktapp.nwpu.edu.cn/berserker-auth/cas/login/supwisdom?targetUrl=https%3A%2F%2Fyktapp.nwpu.edu.cn%2Fplat")!

        XCTAssertTrue(
            policy.isAuthenticationRedirect(
                bootstrap,
                target: .electricity,
                allowsExpectedElectricityCASBootstrap: false
            )
        )
    }

    func testExpectedElectricitySSOIntermediateHopsRemainAllowedDuringBootstrap() {
        let policy = VisibleCollectionNavigationPolicy()
        let urls = [
            URL(string: "https://uis.nwpu.edu.cn/cas/login?service=https%3A%2F%2Fyktapp.nwpu.edu.cn%2Fplat")!,
            URL(string: "https://authserver.nwpu.edu.cn/authserver/login?service=card")!,
            URL(string: "https://passport.nwpu.edu.cn/sso/login?service=card")!,
            URL(string: "https://yktapp.nwpu.edu.cn/berserker-base/redirect?appId=36")!,
            URL(string: "https://yktapp.nwpu.edu.cn/plat")!,
            URL(string: "https://yktapp.nwpu.edu.cn/jfdt/charge/feeitem/toAppitem")!,
        ]

        for url in urls {
            XCTAssertTrue(policy.isExpectedElectricityAuthenticationIntermediate(url), url.absoluteString)
            XCTAssertFalse(
                policy.isAuthenticationRedirect(
                    url,
                    target: .electricity,
                    allowsExpectedElectricityCASBootstrap: true
                ),
                url.absoluteString
            )
        }
    }

    func testElectricitySSOErrorIntermediateStillFailsClosed() {
        let policy = VisibleCollectionNavigationPolicy()
        let error = URL(string: "https://uis.nwpu.edu.cn/cas/login?error=access_denied")!

        XCTAssertFalse(policy.isExpectedElectricityAuthenticationIntermediate(error))
        XCTAssertTrue(
            policy.isAuthenticationRedirect(
                error,
                target: .electricity,
                allowsExpectedElectricityCASBootstrap: true
            )
        )
    }

    func testElectricityCASAndUniversitySSOHopsStayVisibleDuringBootstrap() {
        let policy = VisibleCollectionNavigationPolicy()
        let cardCAS = URL(string: "https://yktapp.nwpu.edu.cn/berserker-auth/cas/login?service=https%3A%2F%2Fyktapp.nwpu.edu.cn%2Fplat")!
        let universitySSO = URL(string: "https://uis.nwpu.edu.cn/cas/login?service=https%3A%2F%2Fyktapp.nwpu.edu.cn%2Fplat")!

        XCTAssertFalse(
            policy.isAuthenticationRedirect(
                cardCAS,
                target: .electricity,
                allowsExpectedElectricityCASBootstrap: true
            )
        )
        XCTAssertFalse(
            policy.isAuthenticationRedirect(
                universitySSO,
                target: .electricity,
                allowsExpectedElectricityCASBootstrap: true
            )
        )
        XCTAssertTrue(
            policy.isAuthenticationRedirect(
                URL(string: "https://yktapp.nwpu.edu.cn/error/unauthorized")!,
                target: .electricity,
                allowsExpectedElectricityCASBootstrap: true
            )
        )
    }

    func testOrdinarySSOLoginRedirectStillRequiresAuthentication() {
        let policy = VisibleCollectionNavigationPolicy()
        let login = URL(string: "https://passport.nwpu.edu.cn/cas/login?service=https%3A%2F%2Fjwxt.nwpu.edu.cn%2Fstudent")!

        XCTAssertTrue(
            policy.isAuthenticationRedirect(
                login,
                target: .education,
                allowsExpectedElectricityCASBootstrap: false
            )
        )
    }

    func testElectricityTokenHandoffUsesBerserkerBaseRedirectContract() {
        XCTAssertEqual(
            VisibleCollectionNavigationPolicy.electricityRedirectPath,
            "/berserker-base/redirect"
        )
        XCTAssertEqual(VisibleCollectionNavigationPolicy.electricityRedirectAppID, "36")
        XCTAssertEqual(VisibleCollectionNavigationPolicy.electricityRedirectType, "app")
        XCTAssertEqual(VisibleCollectionNavigationPolicy.electricityRedirectLoginFrom, "h5")
        XCTAssertEqual(VisibleCollectionNavigationPolicy.electricityRedirectTokenParameter, "synjones-auth")
    }

    func testElectricityPageTokenAndAuthenticationEntryContract() {
        XCTAssertEqual(
            VisibleCollectionNavigationPolicy.electricityTokenCookieNames,
            ["synjones-auth", "access_token", "accessToken", "synjonesAuth", "token"]
        )
        XCTAssertEqual(
            VisibleCollectionNavigationPolicy.electricityAuthEntryLabels,
            ["统一身份认证", "统一登录", "更多登录方式"]
        )
    }

    func testElectricityRedirectURLRequiresTokenAndPreservesAndroidQueryContract() throws {
        XCTAssertNil(VisibleCollectionNavigationPolicy.electricityRedirectURL(token: "  "))

        let url = try XCTUnwrap(
            VisibleCollectionNavigationPolicy.electricityRedirectURL(token: "token+/=")
        )
        XCTAssertEqual(url.host, "yktapp.nwpu.edu.cn")
        XCTAssertEqual(url.path, "/berserker-base/redirect")
        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map {
                "\($0.name)=\($0.value ?? "")"
            },
            [
                "appId=36",
                "type=app",
                "synjones-auth=token+/=",
                "loginFrom=h5",
            ]
        )
    }

    func testElectricityPageURLRequiresTokenAndUsesDirectAndroidFeeContract() throws {
        XCTAssertNil(VisibleCollectionNavigationPolicy.electricityPageURL(token: "  "))

        let url = try XCTUnwrap(
            VisibleCollectionNavigationPolicy.electricityPageURL(token: "token+/=")
        )
        XCTAssertEqual(url.host, "yktapp.nwpu.edu.cn")
        XCTAssertEqual(url.path, "/jfdt/charge/feeitem/toAppitem")
        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map {
                "\($0.name)=\($0.value ?? "")"
            },
            [
                "feeitemid=182",
                "synjones-auth=token+/=",
                "appId=36",
                "loginFrom=h5",
                "type=app",
            ]
        )
    }

    func testElectricityBootstrapAllowanceSurvivesTokenHandoffUntilTheJfdtPage() {
        let policy = VisibleCollectionNavigationPolicy()
        let urls = [
            URL(string: "https://yktapp.nwpu.edu.cn/berserker-base/redirect?appId=36&type=app")!,
            URL(string: "https://yktapp.nwpu.edu.cn/berserker-auth/cas/login?service=card")!,
            URL(string: "https://uis.nwpu.edu.cn/cas/login?service=card")!,
            URL(string: "https://yktapp.nwpu.edu.cn/plat")!,
        ]

        for url in urls {
            XCTAssertTrue(
                policy.shouldMaintainElectricityBootstrapAllowance(after: url),
                url.absoluteString
            )
        }
        XCTAssertFalse(policy.shouldMaintainElectricityBootstrapAllowance(after:
            URL(string: "https://yktapp.nwpu.edu.cn/jfdt/charge/feeitem/toAppitem")!
        ))
        XCTAssertFalse(policy.shouldMaintainElectricityBootstrapAllowance(after:
            URL(string: "https://uis.nwpu.edu.cn/cas/login?error=access_denied")!
        ))
    }

    func testRedirectLoadingShellUsesBoundedDirectFeePageFallback() {
        let policy = VisibleCollectionNavigationPolicy()
        let redirect = URL(
            string: "https://yktapp.nwpu.edu.cn/berserker-base/redirect?appId=36&type=app"
        )!
        let limit = VisibleCollectionNavigationPolicy.electricityDirectFallbackHandoffProbeLimit

        XCTAssertFalse(policy.shouldStartElectricityDirectFallback(
            afterHandoffProbes: limit - 1,
            at: redirect,
            hasAlreadyTriedDirectPage: false
        ))
        XCTAssertTrue(policy.shouldStartElectricityDirectFallback(
            afterHandoffProbes: limit,
            at: redirect,
            hasAlreadyTriedDirectPage: false
        ))
        XCTAssertFalse(policy.shouldStartElectricityDirectFallback(
            afterHandoffProbes: limit,
            at: redirect,
            hasAlreadyTriedDirectPage: true
        ))
        XCTAssertFalse(policy.shouldStartElectricityDirectFallback(
            afterHandoffProbes: limit,
            at: URL(string: "https://yktapp.nwpu.edu.cn/jfdt/charge/feeitem/toAppitem")!,
            hasAlreadyTriedDirectPage: false
        ))
        XCTAssertFalse(policy.shouldStartElectricityDirectFallback(
            afterHandoffProbes: limit,
            at: URL(string: "https://example.invalid/berserker-base/redirect")!,
            hasAlreadyTriedDirectPage: false
        ))
    }

    func testDirectFeePageStopsAfterBoundedMissingBalanceProbes() {
        let policy = VisibleCollectionNavigationPolicy()
        let limit = VisibleCollectionNavigationPolicy.electricityMissingBalanceProbeLimit

        XCTAssertFalse(policy.shouldFinishElectricityAfterMissingBalance(
            afterBalanceProbes: limit - 1,
            hasAlreadyTriedDirectPage: true
        ))
        XCTAssertTrue(policy.shouldFinishElectricityAfterMissingBalance(
            afterBalanceProbes: limit,
            hasAlreadyTriedDirectPage: true
        ))
        XCTAssertFalse(policy.shouldFinishElectricityAfterMissingBalance(
            afterBalanceProbes: limit,
            hasAlreadyTriedDirectPage: false
        ))
    }

    func testDirectFallbackStillOnRedirectShellStopsAfterItsOwnBoundedProbes() {
        let policy = VisibleCollectionNavigationPolicy()
        let redirect = URL(
            string: "https://yktapp.nwpu.edu.cn/berserker-base/redirect?appId=36&type=app"
        )!
        let limit = VisibleCollectionNavigationPolicy.electricityDirectFallbackRedirectProbeLimit

        XCTAssertFalse(policy.shouldFinishElectricityAfterDirectFallbackRedirect(
            afterFallbackProbes: limit - 1,
            at: redirect,
            hasAlreadyTriedDirectPage: true
        ))
        XCTAssertTrue(policy.shouldFinishElectricityAfterDirectFallbackRedirect(
            afterFallbackProbes: limit,
            at: redirect,
            hasAlreadyTriedDirectPage: true
        ))
        XCTAssertFalse(policy.shouldFinishElectricityAfterDirectFallbackRedirect(
            afterFallbackProbes: limit,
            at: redirect,
            hasAlreadyTriedDirectPage: false
        ))
        XCTAssertFalse(policy.shouldFinishElectricityAfterDirectFallbackRedirect(
            afterFallbackProbes: limit,
            at: URL(string: "https://yktapp.nwpu.edu.cn/jfdt/charge/feeitem/toAppitem")!,
            hasAlreadyTriedDirectPage: true
        ))
    }

    func testSanitizedInspectionURLKeyDropsTokenQueryAndFragment() throws {
        let url = URL(
            string: "https://jwxt.nwpu.edu.cn/student/home?synjones-auth=secret-token&semester=2026#details"
        )!

        XCTAssertEqual(
            try XCTUnwrap(VisibleCollectionNavigationPolicy.sanitizedInspectionURLKey(for: url)),
            "https://jwxt.nwpu.edu.cn/student/home"
        )
    }

    func testOnlyExpectedWebViewCancellationErrorsAreIgnoredDuringElectricityRedirect() {
        XCTAssertTrue(VisibleCollectionNavigationPolicy.isExpectedWebViewNavigationInterruption(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        ))
        XCTAssertTrue(VisibleCollectionNavigationPolicy.isExpectedWebViewNavigationInterruption(
            NSError(domain: "WKErrorDomain", code: 102)
        ))
        XCTAssertFalse(VisibleCollectionNavigationPolicy.isExpectedWebViewNavigationInterruption(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        ))
        XCTAssertFalse(VisibleCollectionNavigationPolicy.isExpectedWebViewNavigationInterruption(
            NSError(domain: "WKErrorDomain", code: 1)
        ))
    }

    func testCancellationErrorsRequireAnActiveElectricityHandoffBeforeTheyAreIgnored() {
        let cancellation = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)

        XCTAssertFalse(VisibleCollectionNavigationPolicy.isExpectedWebViewNavigationInterruption(
            cancellation,
            duringElectricityHandoff: false
        ))
        XCTAssertTrue(VisibleCollectionNavigationPolicy.isExpectedWebViewNavigationInterruption(
            cancellation,
            duringElectricityHandoff: true
        ))
    }
}
