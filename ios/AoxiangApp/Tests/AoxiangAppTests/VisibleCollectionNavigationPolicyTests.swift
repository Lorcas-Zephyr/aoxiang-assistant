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
}
