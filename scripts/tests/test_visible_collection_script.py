import re
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_FILE = (
    REPO_ROOT
    / "ios"
    / "AoxiangApp"
    / "Sources"
    / "AoxiangApp"
    / "VisibleAuthenticationWebView.swift"
)


class VisibleCollectionScriptTest(unittest.TestCase):
    def assert_embedded_script_is_syntax_valid(self, declaration_pattern: str, name: str):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        match = re.search(declaration_pattern, source, flags=re.DOTALL)
        self.assertIsNotNone(match, f"the {name} script must remain embedded in the WebView model")

        script = "function __aoxiangCollectionWrapper() {\n" + match.group(1) + "\n}\n"
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / f"{name}.js"
            path.write_text(script, encoding="utf-8")
            completed = subprocess.run(
                ["node", "--check", str(path)],
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(
            completed.returncode,
            0,
            completed.stderr or completed.stdout,
        )

    def test_embedded_webview_collection_script_is_javascript_syntax_valid(self):
        self.assert_embedded_script_is_syntax_valid(
            r"private static let educationCollectionScript = #\"\"\"(.*?)\"\"\"#",
            "visible-education-collection",
        )
        source = SOURCE_FILE.read_text(encoding="utf-8")
        # The portal has shipped both JSON.parse bootstrap strings and direct
        # arrays/window variables. Keep the visible path from timing out when
        # only the representation changes.
        self.assertIn("window.semesters", source)
        self.assertIn("document.querySelector('#studentId')", source)
        self.assertIn("window.studentId", source)
        self.assertIn("JSON.parse(raw)", source)
        self.assertIn("teacherValues", source)
        self.assertIn("teacherName", source)
        self.assertIn("nameZh", source)
        self.assertNotIn("Array.isArray(activity.teachers) ? activity.teachers.map(clean)", source)
        self.assertIn("term.dataSemester", source)
        self.assertIn("scheduleStudentId", source)
        self.assertIn("Object.values(raw)", source)

    def test_embedded_electricity_script_is_javascript_syntax_valid_and_supports_portal_variants(self):
        self.assert_embedded_script_is_syntax_valid(
            r'private static let electricityBalanceScript = #\"\"\"(.*?)\"\"\"#',
            "visible-electricity-collection",
        )
        self.assert_embedded_script_is_syntax_valid(
            r'private static let electricityPortalBootstrapScript = #\"\"\"(.*?)\"\"\"#',
            "visible-electricity-portal-bootstrap",
        )
        source = SOURCE_FILE.read_text(encoding="utf-8")
        self.assertIn("app.__vueParentComponent", source)
        self.assertIn("app.__vue_app__", source)
        self.assertIn("performance.getEntriesByType('resource')", source)
        self.assertIn("'/jfdt/charge/feeitem/toAppitem'", source)
        self.assertIn('electricityRedirectPath = "/berserker-base/redirect"', source)
        self.assertIn("target.searchParams.set('feeitemid', '182')", source)
        self.assertIn("target.searchParams.set('appId', '36')", source)
        self.assertIn("target.searchParams.set('type', 'app')", source)
        self.assertIn("target.searchParams.set('synjones-auth', token)", source)
        self.assertIn("target.searchParams.set('loginFrom', 'h5')", source)
        self.assertIn("document.cookie", source)
        self.assertIn("readCookie", source)
        self.assertIn("auth_clicked", source)
        self.assertIn("window.__aoxiangElectricityBalance = null", source)
        self.assertIn("text && typeof text === 'object'", source)
        self.assertIn("const containers =", source)
        # The visible card page may need an SSO hand-off and a settlement
        # request, but the foreground sheet must return control promptly when
        # the portal never provides a balance.
        self.assertIn("30_000_000_000", source)
        self.assertIn("isExpectedElectricityAuthenticationIntermediate", source)
        self.assertIn("Object.entries(value)", source)
        self.assertIn("scheduleElectricityEvaluation", source)
        self.assertIn("document.cookie", source)
        self.assertIn("clickAuthEntry", source)
        self.assertIn("window.__aoxiangElectricityBalance = null", source)
        self.assertIn("aoxiang-electricity-balance", source)
        self.assertIn("collectFrames", source)
        # Match Android's token-first portal hand-off while preserving the
        # visible login-shell guard and the bounded direct fee-item fallback.
        self.assertNotIn("const portalReady", source)
        self.assertIn("请登录", source)
        self.assertIn("electricityRedirectAttempted", source)
        self.assertIn("electricityPortalBootstrapScript", source)
        self.assertIn("__AOXIANG_REDIRECT_ATTEMPTED__", source)
        self.assertIn("electricityDirectFallbackAttempted", source)
        self.assertIn("electricityDirectFallbackScript", source)
        self.assertIn("frameWindows", source)
        self.assertIn("readQueryToken", source)
        self.assertIn("currentWindow.document.cookie", source)

    def test_direct_fallback_has_a_login_shell_guard_and_explicit_result(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        fallback_script = source.split(
            "private static let electricityDirectFallbackScript = #\"\"\"", 1
        )[1].split("\"\"\"#", 1)[0]

        self.assertIn("const loginShell", fallback_script)
        self.assertIn("return 'needs_login'", fallback_script)
        self.assertIn("return 'direct_started'", fallback_script)

    def test_electricity_resource_scan_uses_one_shared_deadline(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        balance_script = source.split(
            "private static let electricityBalanceScript = #\"\"\"", 1
        )[1].split("\"\"\"#", 1)[0]

        self.assertIn("const resourceScanDeadline", balance_script)
        self.assertIn("const remaining = resourceScanDeadline - Date.now()", balance_script)
        self.assertIn("Math.min(900, remaining)", balance_script)

    def test_redirect_loading_shell_has_a_bounded_direct_fee_page_escape(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        handler_prefix = source.split(
            "private func handleElectricityNavigation(in webView: WKWebView) {", 1
        )[1].split(
            '        if path == VisibleCollectionNavigationPolicy.electricityRedirectPath ||', 1
        )[0]
        redirect_branch = source.split(
            'if path == VisibleCollectionNavigationPolicy.electricityRedirectPath ||'
        )[1].split('        if path.hasPrefix("/plat") {', 1)[0]

        self.assertIn("electricityHandoffProbeCount", source)
        self.assertIn("electricityDirectFallbackHandoffProbeLimit", source)
        self.assertIn("shouldStartElectricityDirectFallback", redirect_branch)
        self.assertIn("startElectricityDirectFallback(in: webView)", redirect_branch)
        self.assertIn("shouldFinishElectricityAfterDirectFallbackRedirect", handler_prefix)
        poll_body = source.split("private func scheduleElectricityEvaluation() {")[1].split(
            "    /// Keeps the card-platform hand-off entirely", 1
        )[0]
        self.assertIn("isElectricityRedirectLoadingShell(self.webView.url)", poll_body)
        self.assertIn("electricityHandoffProbeCount += 1", poll_body)

    def test_missing_direct_fee_balance_has_a_bounded_terminal_result(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        missing_balance_body = source.split(
            "private func handleMissingElectricityBalance(in webView: WKWebView) {", 1
        )[1].split("    private func startElectricityDirectFallback", 1)[0]

        self.assertIn("electricityMissingBalanceProbeLimit", source)
        self.assertIn("electricityBalanceProbeCount += 1", missing_balance_body)
        self.assertIn("shouldFinishElectricityAfterMissingBalance", missing_balance_body)
        self.assertIn("finishElectricity(.failure(PortalCollectionFailure.retryable(.serverUnavailable)))", missing_balance_body)

    def test_direct_fee_page_has_its_own_bounded_balance_probe_window(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        fallback_body = source.split(
            "private func startElectricityDirectFallback(in webView: WKWebView) {", 1
        )[1].split("    private func javascriptBoolean", 1)[0]

        # The recovery route is a new page with its own delayed Vue/API render.
        # Earlier failures determine that recovery is needed, but must not make
        # the new page fail after only a couple of probes.
        self.assertIn("electricityBalanceProbeCount = 0", fallback_body)

    def test_electricity_probe_does_not_depend_on_a_navigation_callback(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        collection_body = source.split(
            "public func collectElectricityBalance() async throws -> Double {", 1
        )[1].split(
            "    /// Reads the student portrait", 1
        )[0]
        self.assertIn("webView.load(URLRequest(url: electricityLoginURL))", collection_body)
        self.assertIn("scheduleElectricityEvaluation()", collection_body)

        poll_body = source.split("private func scheduleElectricityEvaluation() {", 1)[1].split(
            "    /// Keeps the card-platform hand-off", 1
        )[0]
        self.assertIn("self.handleElectricityNavigation(in: self.webView)", poll_body)
        self.assertIn("self.electricityContinuation != nil", poll_body)
        self.assertIn("self.scheduleElectricityEvaluation()", poll_body)

    def test_electricity_network_capture_script_is_javascript_syntax_valid(self):
        self.assert_embedded_script_is_syntax_valid(
            r'private static let electricityNetworkCaptureScript = #\"\"\"(.*?)\"\"\"#',
            "visible-electricity-network-capture",
        )


if __name__ == "__main__":
    unittest.main()
