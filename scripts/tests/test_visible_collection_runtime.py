import json
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


class VisibleCollectionRuntimeTest(unittest.TestCase):
    def embedded_script(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        match = re.search(
            r"private static let educationCollectionScript = #\"\"\"(.*?)\"\"\"#",
            source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match)
        return match.group(1)

    def electricity_script(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        match = re.search(
            r"private static let electricityBalanceScript = #\"\"\"(.*?)\"\"\"#",
            source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match)
        return match.group(1)

    def electricity_capture_script(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        match = re.search(
            r"private static let electricityNetworkCaptureScript = #\"\"\"(.*?)\"\"\"#",
            source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match)
        return match.group(1)

    def electricity_portal_script(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        match = re.search(
            r"private static let electricityPortalBootstrapScript = #\"\"\"(.*?)\"\"\"#",
            source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match)
        return match.group(1)

    def electricity_direct_fallback_script(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        match = re.search(
            r"private static let electricityDirectFallbackScript = #\"\"\"(.*?)\"\"\"#",
            source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match)
        return match.group(1)

    def run_electricity_script(self, setup, timeout=5):
        harness = f"""
{setup}
async function execute() {{
{self.electricity_script()}
}}
execute().then(value => process.stdout.write(JSON.stringify(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "electricity-runtime.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(
                ["node", str(path)],
                capture_output=True,
                check=False,
                timeout=timeout,
            )
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        return json.loads(stdout)

    def run_electricity_capture_script(self, setup, action="", timeout=5):
        harness = f"""
{setup}
{self.electricity_capture_script()}
{action}
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "electricity-capture-runtime.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(
                ["node", str(path)],
                capture_output=True,
                check=False,
                timeout=timeout,
            )
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        return json.loads(stdout)

    def run_electricity_portal_script(self, setup, redirect_attempted=False, timeout=5):
        attempted = "true" if redirect_attempted else "false"
        script = self.electricity_portal_script().replace(
            "__AOXIANG_REDIRECT_ATTEMPTED__", attempted
        ).strip()
        harness = f"""
{setup}
async function execute() {{
  return {script};
}}
Promise.resolve(execute()).then(value => process.stdout.write(JSON.stringify({{
  action: value,
  href: globalThis.location && globalThis.location.href
}}))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "electricity-portal-runtime.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(
                ["node", str(path)],
                capture_output=True,
                check=False,
                timeout=timeout,
            )
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        return json.loads(stdout)

    def run_electricity_direct_fallback_script(self, setup, timeout=5):
        harness = f"""
{setup}
async function execute() {{
  return {self.electricity_direct_fallback_script().strip()};
}}
Promise.resolve(execute()).then(value => process.stdout.write(JSON.stringify({{
  action: value,
  href: globalThis.location && globalThis.location.href
}}))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "electricity-direct-fallback-runtime.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(
                ["node", str(path)],
                capture_output=True,
                check=False,
                timeout=timeout,
            )
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        return json.loads(stdout)

    def test_electricity_script_reads_nested_api_response_map_show_data(self):
        result = self.run_electricity_script("""
const document = { querySelector: () => null, body: { innerText: '加载中' } };
const window = {};
globalThis.document = document;
globalThis.window = window;
globalThis.location = { origin: 'https://yktapp.nwpu.edu.cn' };
globalThis.performance = {
  getEntriesByType: () => [{ name: 'https://yktapp.nwpu.edu.cn/jfdt/api/feeitem/balance' }]
};
globalThis.fetch = async () => ({
  ok: true,
  text: async () => JSON.stringify({
    map: { showData: { balance: '18.52' } }
  })
});
""")
        self.assertEqual(result, 18.52)

    def test_electricity_portal_uses_token_from_same_origin_iframe_storage(self):
        # The card portal can render the account card in a same-origin frame.
        # The bootstrap must read that frame's short-lived token and navigate
        # the visible top-level WebView through the Android-compatible direct
        # fee-item route.
        result = self.run_electricity_portal_script("""
const location = {
  href: 'https://yktapp.nwpu.edu.cn/plat',
  origin: 'https://yktapp.nwpu.edu.cn',
  replace: target => { location.href = target; }
};
const frameDocument = {
  cookie: '',
  body: { innerText: '校园卡 账户余额' },
  querySelectorAll: () => []
};
const frameWindow = {
  document: frameDocument,
  location: { href: 'https://yktapp.nwpu.edu.cn/plat/card' },
  sessionStorage: { getItem: key => key === 'access_token' ? 'frame-token' : '' },
  localStorage: { getItem: () => '' }
};
const document = {
  cookie: '',
  body: { innerText: '加载中' },
  querySelectorAll: () => [{ contentWindow: frameWindow, contentDocument: frameDocument }]
};
const window = {
  document,
  location,
  sessionStorage: { getItem: () => '' },
  localStorage: { getItem: () => '' }
};
globalThis.document = document;
globalThis.window = window;
globalThis.location = location;
""")
        self.assertEqual(result.get("action"), "direct_started", result)
        self.assertIn("/jfdt/charge/feeitem/toAppitem?", result["href"])
        self.assertIn("feeitemid=182", result["href"])
        self.assertIn("synjones-auth=frame-token", result["href"])

    def test_electricity_portal_uses_token_from_same_origin_iframe_cookie(self):
        result = self.run_electricity_portal_script("""
const location = {
  href: 'https://yktapp.nwpu.edu.cn/plat',
  origin: 'https://yktapp.nwpu.edu.cn',
  replace: target => { location.href = target; }
};
const frameDocument = {
  cookie: 'synjones-auth=frame-cookie-token',
  body: { innerText: '校园卡 账户余额' },
  querySelectorAll: () => []
};
const frameWindow = {
  document: frameDocument,
  location: { href: 'https://yktapp.nwpu.edu.cn/plat/card' },
  sessionStorage: { getItem: () => '' },
  localStorage: { getItem: () => '' }
};
const document = {
  cookie: '',
  body: { innerText: '加载中' },
  querySelectorAll: () => [{ contentWindow: frameWindow, contentDocument: frameDocument }]
};
const window = {
  document,
  location,
  sessionStorage: { getItem: () => '' },
  localStorage: { getItem: () => '' }
};
globalThis.document = document;
globalThis.window = window;
globalThis.location = location;
""")
        self.assertEqual(result.get("action"), "direct_started", result)
        self.assertIn("/jfdt/charge/feeitem/toAppitem?", result["href"])
        self.assertIn("feeitemid=182", result["href"])
        self.assertIn("synjones-auth=frame-cookie-token", result["href"])

    def test_electricity_portal_uses_direct_fee_page_after_redirect_attempt(self):
        result = self.run_electricity_portal_script("""
const location = {
  href: 'https://yktapp.nwpu.edu.cn/plat',
  origin: 'https://yktapp.nwpu.edu.cn',
  replace: target => { location.href = target; }
};
const frameDocument = {
  cookie: '',
  body: { innerText: '校园卡 账户余额' },
  querySelectorAll: () => []
};
const frameWindow = {
  document: frameDocument,
  location: { href: 'https://yktapp.nwpu.edu.cn/plat/card' },
  sessionStorage: { getItem: key => key === 'synjones-auth' ? 'fallback-token' : '' },
  localStorage: { getItem: () => '' }
};
const document = {
  cookie: '',
  body: { innerText: '加载中' },
  querySelectorAll: () => [{ contentWindow: frameWindow, contentDocument: frameDocument }]
};
const window = {
  document,
  location,
  sessionStorage: { getItem: () => '' },
  localStorage: { getItem: () => '' }
};
globalThis.document = document;
globalThis.window = window;
globalThis.location = location;
""", redirect_attempted=True)
        self.assertEqual(result.get("action"), "direct_started", result)
        self.assertIn("/jfdt/charge/feeitem/toAppitem?", result["href"])
        self.assertIn("feeitemid=182", result["href"])
        self.assertIn("synjones-auth=fallback-token", result["href"])

    def test_electricity_portal_hands_off_top_level_token_while_query_information_shell_is_loading(self):
        # The deployed /plat page can remain a non-login "querying
        # information" shell indefinitely, even though its own sessionStorage
        # already has the short-lived card token. Android hands off at that
        # point; the visible iOS flow must do the same without waiting for an
        # account-balance card to render.
        result = self.run_electricity_portal_script("""
const location = {
  href: 'https://yktapp.nwpu.edu.cn/plat',
  origin: 'https://yktapp.nwpu.edu.cn',
  replace: target => { location.href = target; }
};
const document = {
  cookie: '',
  body: { innerText: '查询信息 加载中' },
  querySelectorAll: () => []
};
const window = {
  document,
  location,
  sessionStorage: { getItem: key => key === 'synjones-auth' ? 'loading-shell-token' : '' },
  localStorage: { getItem: () => '' }
};
globalThis.document = document;
globalThis.window = window;
globalThis.location = location;
""")
        self.assertEqual(result.get("action"), "direct_started", result)
        self.assertIn("/jfdt/charge/feeitem/toAppitem?", result["href"])
        self.assertIn("feeitemid=182", result["href"])
        self.assertIn("synjones-auth=loading-shell-token", result["href"])

    def test_electricity_portal_hands_off_loading_shell_token_to_direct_fee_page_after_redirect_attempt(self):
        # If the Berserker redirect returned to /plat, the same non-login
        # loading shell must use its page-owned token for the one bounded
        # direct fee-page recovery path rather than wait for a balance marker.
        result = self.run_electricity_portal_script("""
const location = {
  href: 'https://yktapp.nwpu.edu.cn/plat',
  origin: 'https://yktapp.nwpu.edu.cn',
  replace: target => { location.href = target; }
};
const frameDocument = {
  cookie: '',
  body: { innerText: '查询信息 正在加载' },
  querySelectorAll: () => []
};
const frameWindow = {
  document: frameDocument,
  location: { href: 'https://yktapp.nwpu.edu.cn/plat/card' },
  sessionStorage: { getItem: key => key === 'access_token' ? 'iframe-loading-token' : '' },
  localStorage: { getItem: () => '' }
};
const document = {
  cookie: '',
  body: { innerText: '查询信息 加载中' },
  querySelectorAll: () => [{ contentWindow: frameWindow, contentDocument: frameDocument }]
};
const window = {
  document,
  location,
  sessionStorage: { getItem: () => '' },
  localStorage: { getItem: () => '' }
};
globalThis.document = document;
globalThis.window = window;
globalThis.location = location;
""", redirect_attempted=True)
        self.assertEqual(result.get("action"), "direct_started", result)
        self.assertIn("/jfdt/charge/feeitem/toAppitem?", result["href"])
        self.assertIn("feeitemid=182", result["href"])
        self.assertIn("synjones-auth=iframe-loading-token", result["href"])

    def test_electricity_portal_never_hands_off_a_stale_token_from_login_shell(self):
        # A stale token is not authority to bypass a visible login challenge.
        # The page-owned token must only drive the non-login /plat hand-off.
        result = self.run_electricity_portal_script("""
const location = {
  href: 'https://yktapp.nwpu.edu.cn/plat',
  origin: 'https://yktapp.nwpu.edu.cn',
  replace: target => { location.href = target; }
};
const document = {
  cookie: '',
  body: { innerText: '请登录 查询信息' },
  querySelectorAll: () => []
};
const window = {
  document,
  location,
  sessionStorage: { getItem: key => key === 'synjones-auth' ? 'stale-token' : '' },
  localStorage: { getItem: () => '' }
};
globalThis.document = document;
globalThis.window = window;
globalThis.location = location;
""")
        self.assertEqual(result.get("action"), "waiting", result)
        self.assertEqual(result["href"], "https://yktapp.nwpu.edu.cn/plat")

    def test_electricity_direct_fallback_never_hands_off_a_stale_token_from_login_shell(self):
        # The fallback runs after a redirect stalls. It must still respect a
        # newly rendered login page instead of recovering with a token left in
        # WebKit storage from an earlier session.
        result = self.run_electricity_direct_fallback_script("""
const location = {
  href: 'https://yktapp.nwpu.edu.cn/berserker-base/redirect?appId=36',
  origin: 'https://yktapp.nwpu.edu.cn',
  replace: target => { location.href = target; }
};
const document = {
  cookie: '',
  body: { innerText: '请登录，登录信息已失效' }
};
const window = {
  document,
  location,
  sessionStorage: { getItem: key => key === 'synjones-auth' ? 'stale-token' : '' },
  localStorage: { getItem: () => '' }
};
globalThis.document = document;
globalThis.window = window;
globalThis.location = location;
""")
        self.assertEqual(result.get("action"), "needs_login", result)
        self.assertEqual(
            result["href"],
            "https://yktapp.nwpu.edu.cn/berserker-base/redirect?appId=36",
        )

    def test_electricity_portal_clicks_auth_entry_in_same_origin_iframe(self):
        result = self.run_electricity_portal_script("""
const location = {
  href: 'https://yktapp.nwpu.edu.cn/plat',
  origin: 'https://yktapp.nwpu.edu.cn',
  replace: target => { location.href = target; }
};
const authEntry = {
  innerText: '统一身份认证',
  closest: () => authEntry,
  click: () => { location.href = 'https://yktapp.nwpu.edu.cn/plat/auth-clicked'; }
};
const frameDocument = {
  cookie: '',
  body: { innerText: '请登录' },
  querySelectorAll: () => [authEntry]
};
const frameWindow = {
  document: frameDocument,
  location: { href: 'https://yktapp.nwpu.edu.cn/plat/card' },
  sessionStorage: { getItem: () => '' },
  localStorage: { getItem: () => '' }
};
const document = {
  cookie: '',
  body: { innerText: '加载中' },
  querySelectorAll: () => [{ contentWindow: frameWindow, contentDocument: frameDocument }]
};
const window = {
  document,
  location,
  sessionStorage: { getItem: () => '' },
  localStorage: { getItem: () => '' }
};
globalThis.document = document;
globalThis.window = window;
globalThis.location = location;
""")
        self.assertEqual(result.get("action"), "auth_clicked", result)
        self.assertEqual(result["href"], "https://yktapp.nwpu.edu.cn/plat/auth-clicked")

    def test_electricity_portal_ignores_cross_origin_iframe_token(self):
        # A frame that is not same-origin must never contribute a token or
        # trigger a card-platform redirect, even if a test double exposes its
        # document object.
        result = self.run_electricity_portal_script("""
const location = {
  href: 'https://yktapp.nwpu.edu.cn/plat',
  origin: 'https://yktapp.nwpu.edu.cn',
  replace: target => { location.href = target; }
};
const frameDocument = {
  cookie: 'synjones-auth=foreign-token',
  body: { innerText: '账户余额' },
  querySelectorAll: () => []
};
const frameWindow = {
  document: frameDocument,
  location: { href: 'https://untrusted.example/card' },
  sessionStorage: { getItem: () => 'foreign-token' },
  localStorage: { getItem: () => '' }
};
const document = {
  cookie: '',
  body: { innerText: '加载中' },
  querySelectorAll: () => [{ contentWindow: frameWindow, contentDocument: frameDocument }]
};
const window = {
  document,
  location,
  sessionStorage: { getItem: () => '' },
  localStorage: { getItem: () => '' }
};
globalThis.document = document;
globalThis.window = window;
globalThis.location = location;
""")
        self.assertEqual(result.get("action"), "waiting", result)
        self.assertEqual(result["href"], "https://yktapp.nwpu.edu.cn/plat")

    def test_electricity_script_reads_nested_vue_response_map_show_data(self):
        result = self.run_electricity_script("""
const app = {
  __vue__: {
    aboutEleric: {
      electricInfo: {
        response: { map: { showData: { '剩余金额': '￥21.75' } } }
      }
    }
  }
};
const document = { querySelector: selector => selector === '#app' ? app : null, body: { innerText: '' } };
const window = {};
globalThis.document = document;
globalThis.window = window;
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: false, text: async () => '' });
""")
        self.assertEqual(result, 21.75)

    def test_electricity_script_reads_vue3_setup_state_balance_field(self):
        result = self.run_electricity_script("""
const app = {
  __vueParentComponent: {
    setupState: { remainingAmount: '12.75' }
  }
};
const document = { querySelector: selector => selector === '#app' ? app : null, body: { innerText: '' } };
const window = {};
globalThis.document = document;
globalThis.window = window;
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: false, text: async () => '' });
""")
        self.assertEqual(result, 12.75)

    def test_electricity_script_reads_balance_from_same_origin_iframe(self):
        result = self.run_electricity_script("""
const frameDocument = {
  querySelector: selector => selector === '#app' ? {
    __vue__: { aboutEleric: { electricInfo: { '当前剩余电量': '33.40' } } }
  } : null,
  querySelectorAll: () => [],
  body: { innerText: '' }
};
const frameWindow = { document: frameDocument };
const document = {
  querySelector: () => null,
  querySelectorAll: () => [{ contentWindow: frameWindow, contentDocument: frameDocument }],
  body: { innerText: '加载中' }
};
const window = { document };
globalThis.document = document;
globalThis.window = window;
globalThis.location = { origin: 'https://yktapp.nwpu.edu.cn' };
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: false, text: async () => '' });
""")
        self.assertEqual(result, 33.4)

    def test_electricity_script_reads_captured_balance_from_same_origin_iframe(self):
        # A document-start hook runs in subframes too. Its validated scalar
        # lives on the child window, so the main-frame probe must aggregate it
        # even when the child has not rendered a Vue root or visible text yet.
        result = self.run_electricity_script("""
const frameDocument = {
  querySelector: () => null,
  querySelectorAll: () => [],
  body: { innerText: '加载中' }
};
const frameWindow = {
  document: frameDocument,
  __aoxiangElectricityBalance: JSON.stringify({
    data: { map: { showData: { '当前剩余电量': '23.80' } } }
  })
};
const document = {
  querySelector: () => null,
  querySelectorAll: () => [{ contentWindow: frameWindow, contentDocument: frameDocument }],
  body: { innerText: '加载中' }
};
const window = { document };
globalThis.document = document;
globalThis.window = window;
globalThis.location = { origin: 'https://yktapp.nwpu.edu.cn' };
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: false, text: async () => '' });
""")
        self.assertEqual(result, 23.8)

    def test_electricity_script_accepts_balance_captured_from_post_response(self):
        # The portal can populate the card with a POST/XHR response while the
        # DOM remains a loading shell. The document-start capture hook stores
        # only the validated number for the later page probe to read.
        result = self.run_electricity_script("""
const document = { querySelector: () => null, body: { innerText: '加载中' } };
const window = { __aoxiangElectricityBalance: 27.4 };
globalThis.document = document;
globalThis.window = window;
globalThis.location = { origin: 'https://yktapp.nwpu.edu.cn' };
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: false, text: async () => '' });
        """)
        self.assertEqual(result, 27.4)

    def test_electricity_script_decodes_captured_json_before_reading_status_code(self):
        # A few portal builds expose the captured response as a JSON string.
        # The HTTP status/code is not the balance; decode the envelope first.
        result = self.run_electricity_script("""
const document = { querySelector: () => null, body: { innerText: '加载中' } };
const window = {
  __aoxiangElectricityBalance: JSON.stringify({ code: 200, data: { balance: '18.52' } })
};
globalThis.document = document;
globalThis.window = window;
globalThis.location = { origin: 'https://yktapp.nwpu.edu.cn' };
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: false, text: async () => '' });
""")
        self.assertEqual(result, 18.52)

    def test_electricity_script_decodes_json_strings_nested_inside_captured_containers(self):
        # The card platform sometimes serializes the response payload once
        # more before putting it under `data`. The collector must unwrap the
        # JSON string and return the labelled balance, never the envelope's
        # status code.
        result = self.run_electricity_script("""
const document = { querySelector: () => null, body: { innerText: '加载中' } };
const window = { __aoxiangElectricityBalance: {
  code: 200,
  data: JSON.stringify({ map: { showData: { '当前剩余电量': '19.60' } } })
} };
globalThis.document = document;
globalThis.window = window;
globalThis.location = { origin: 'https://yktapp.nwpu.edu.cn' };
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: false, text: async () => '' });
""")
        self.assertEqual(result, 19.6)

    def test_electricity_script_rejects_unstructured_status_text_as_balance(self):
        result = self.run_electricity_script("""
const document = { querySelector: () => null, body: { innerText: '加载中' } };
const window = { __aoxiangElectricityBalance: 'code=200; request accepted' };
globalThis.document = document;
globalThis.window = window;
globalThis.location = { origin: 'https://yktapp.nwpu.edu.cn' };
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: false, text: async () => '' });
""")
        self.assertIsNone(result)

    def test_electricity_script_rejects_json_status_without_balance(self):
        result = self.run_electricity_script("""
const document = { querySelector: () => null, body: { innerText: '加载中' } };
const window = {
  __aoxiangElectricityBalance: JSON.stringify({ code: 200, message: 'ok' })
};
globalThis.document = document;
globalThis.window = window;
globalThis.location = { origin: 'https://yktapp.nwpu.edu.cn' };
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: false, text: async () => '' });
""")
        self.assertIsNone(result)

    def test_electricity_capture_reads_balance_from_post_fetch_response(self):
        result = self.run_electricity_capture_script("""
const window = {};
globalThis.window = window;
globalThis.location = { hostname: 'yktapp.nwpu.edu.cn' };
window.fetch = async () => ({
  clone: () => ({ text: async () => JSON.stringify({
    map: { showData: { '当前剩余电量': '24.60' } }
  }) })
});
window.XMLHttpRequest = undefined;
""", action="""
window.fetch('/jfdt/api/feeitem/balance', { method: 'POST' }).then(() => {
  setTimeout(() => process.stdout.write(JSON.stringify(window.__aoxiangElectricityBalance)), 0);
});
""")
        self.assertEqual(result, 24.6)

    def test_electricity_capture_clears_stale_balance_at_document_start(self):
        result = self.run_electricity_capture_script("""
const window = { __aoxiangElectricityBalance: 99.9 };
globalThis.window = window;
globalThis.location = { hostname: 'yktapp.nwpu.edu.cn' };
window.fetch = async () => ({ clone: () => ({ text: async () => '' }) });
window.XMLHttpRequest = undefined;
""", action="""
process.stdout.write(JSON.stringify(window.__aoxiangElectricityBalance));
""")
        self.assertIsNone(result)

    def test_electricity_capture_publishes_iframe_balance_to_top_frame(self):
        # WKUserScript runs in subframes when forMainFrameOnly is false. The
        # native probe runs in the main frame, so a same-origin iframe must
        # publish its validated scalar through the top frame.
        result = self.run_electricity_capture_script("""
const topWindow = {};
const window = { top: topWindow };
globalThis.window = window;
globalThis.location = { hostname: 'yktapp.nwpu.edu.cn' };
window.fetch = async () => ({
  clone: () => ({ text: async () => JSON.stringify({
    data: { map: { showData: { balance: '22.10' } } }
  }) })
});
window.XMLHttpRequest = undefined;
""", action="""
window.fetch('/jfdt/api/feeitem/balance', { method: 'POST' }).then(() => {
  setTimeout(() => process.stdout.write(JSON.stringify(topWindow.__aoxiangElectricityBalances)), 0);
});
""")
        self.assertEqual(result, [22.1])

    def test_electricity_script_accepts_nested_json_object_captured_from_xhr(self):
        # XHR responseType=json exposes an object rather than responseText.
        # The document-start hook stores the object shape until the page probe
        # can inspect its response/map/showData containers.
        result = self.run_electricity_script("""
const document = { querySelector: () => null, body: { innerText: '加载中' } };
const window = { __aoxiangElectricityBalance: {
  response: { data: { map: { showData: { '剩余金额': '￥31.25' } } } }
} };
globalThis.document = document;
globalThis.window = window;
globalThis.location = { origin: 'https://yktapp.nwpu.edu.cn' };
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: false, text: async () => '' });
""")
        self.assertEqual(result, 31.25)

    def test_electricity_script_reads_dom_balance_without_colon_or_unit(self):
        result = self.run_electricity_script("""
const document = {
  querySelector: () => null,
  body: { innerText: '校园卡\\n剩余金额 18.52' }
};
const window = {};
globalThis.document = document;
globalThis.window = window;
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: false, text: async () => '' });
""")
        self.assertEqual(result, 18.52)

    def test_electricity_script_returns_promptly_for_empty_loading_skeleton(self):
        result = self.run_electricity_script("""
const document = { querySelector: () => null, body: { innerText: '正在加载...' } };
const window = {};
globalThis.document = document;
globalThis.window = window;
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => ({ ok: true, text: async () => '' });
""", timeout=2)
        self.assertIsNone(result)

    def test_electricity_script_has_a_shared_resource_scan_deadline(self):
        # A card page can retain several failed fee URLs in the Performance
        # timeline. The probe must not serially spend 1.8 seconds on every
        # one, otherwise a later balance retry never gets a chance before the
        # native foreground watchdog fires.
        result = self.run_electricity_script("""
const document = { querySelector: () => null, body: { innerText: '正在加载...' } };
const window = {};
globalThis.document = document;
globalThis.window = window;
globalThis.location = { origin: 'https://yktapp.nwpu.edu.cn' };
globalThis.performance = {
  getEntriesByType: () => Array.from({ length: 6 }, (_, index) => ({
    name: 'https://yktapp.nwpu.edu.cn/jfdt/api/feeitem/balance/' + index
  }))
};
globalThis.fetch = (_url, options) => new Promise((_resolve, reject) => {
  options.signal.addEventListener('abort', () => reject(new Error('aborted')));
});
""", timeout=4)
        self.assertIsNone(result)

    def test_education_script_accepts_data_semester_and_returns_sanitized_success(self):
        script = self.embedded_script()
        harness = f"""
const window = {{
  studentId: "student-fixture",
  semesters: [
    {{ dataSemester: "term-fixture", name: "2026 秋", startDate: "2026-08-31", endDate: "2027-01-10" }}
  ]
}};
const document = {{
  querySelector: () => null,
  body: {{ innerText: "" }}
}};
const performance = {{ getEntriesByType: () => [] }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = performance;
globalThis.fetch = async (url) => {{
  const path = String(url).split("?")[0];
  if (path === "/student/for-std/grade/sheet/") return response("<html></html>");
  if (path === "/student/for-std/grade/sheet/info/student-fixture") return response(JSON.stringify({{
    semesterId2studentGrades: {{ "term-fixture": [{{
      published: true,
      course: {{ nameZh: "软件工程", credits: 3 }},
      gp: 4,
      gaGrade: 95,
      gradeDetail: "期末成绩 95"
    }}] }}
  }}));
  if (path === "/student/for-std/student-portrait/getMyGpa") return response(JSON.stringify({{ gpa: 3.76 }}));
  if (path === "/student/for-std/course-table") return response("<html></html>");
  if (path === "/student/ws/semester/get/term-fixture") return response(JSON.stringify({{
    id: "term-fixture", name: "2026 秋", startDate: "2026-08-31", endDate: "2027-01-10"
  }}));
  if (path === "/student/for-std/course-table/semester/term-fixture/print-data/student-fixture") return response(JSON.stringify({{
    studentTableVm: {{ activities: [{{
      courseName: "软件工程", courseCode: "SE-101", credits: 3,
      weekday: 1, startUnit: 1, endUnit: 2, weekIndexes: [1, 2],
      teachers: [{{ nameZh: "张老师" }}], campus: "长安", building: "A", room: "101"
    }}] }}
  }}));
  return response("not found", 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}

async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-runtime.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(
                ["node", str(path)],
                capture_output=True,
                check=False,
            )
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "软件工程")
        self.assertEqual(result["schedule"]["semester"]["id"], "term-fixture")
        self.assertEqual(result["schedule"]["activities"][0]["teachers"], ["张老师"])

    def test_education_script_uses_rendered_grade_table_when_grade_api_has_no_semesters(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{
  querySelectorAll: selector => selector === 'td' ? cells(['数据结构', '3', '4.0', '96', '期末 96']) : [],
  querySelector: () => null
}};
const gradeTable = {{
  querySelectorAll: selector => {{
    if (selector === 'thead th') return cells(['课程名称', '学分', '绩点', '成绩', '成绩构成']);
    if (selector === 'tbody tr' || selector === 'tr') return [gradeRow];
    return [];
  }}
}};
const window = {{}};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
const performance = {{ getEntriesByType: () => [] }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = performance;
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/grade/sheet/') return response('<html><body>学生成绩</body></html>');
  if (path === '/student/for-std/student-portrait/getStdInfo') return response(JSON.stringify({{
    student: {{ id: 'student-fixture' }}
  }}));
  if (path.startsWith('/student/for-std/grade/sheet/info/')) return response('unavailable', 503);
  if (path === '/student/for-std/student-portrait/getMyGpa') return response(JSON.stringify({{ gpa: 3.88 }}));
  if (path === '/student/for-std/course-table') return response(`
    <script>var semesters = [{{"id":"term-fixture","name":"2026 秋","startDate":"2026-08-31","endDate":"2027-01-10"}}];</script>
  `);
  if (path === '/student/ws/semester/get/term-fixture') return response(JSON.stringify({{
    id: 'term-fixture', name: '2026 秋', startDate: '2026-08-31', endDate: '2027-01-10'
  }}));
  if (path === '/student/for-std/course-table/semester/term-fixture/print-data/student-fixture') return response(JSON.stringify({{
    studentTableVm: {{ activities: [] }}
  }}));
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}

async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-dom-fallback.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(
                ["node", str(path)],
                capture_output=True,
                check=False,
            )
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"], [{
            "course": "数据结构",
            "credits": 3,
            "point": 4,
            "score": 96,
            "category": "课程",
            "detail": "期末 96",
        }])
        self.assertEqual(result["schedule"]["semester"]["id"], "term-fixture")

    def test_education_script_maps_grade_columns_by_exact_header_when_columns_are_reordered(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{
  querySelectorAll: selector => selector === 'td'
    ? cells(['必修', '数据结构', '考试', '3', '平时 40 / 期末 48', '95', '4.0', '备注'])
    : []
}};
const gradeTable = {{
  querySelectorAll: selector => {{
    if (selector === 'thead th') return cells(['课程性质', '课程\\n名称', '考核方式', '学分', '成绩构成', '成绩', '绩点', '成绩详情']);
    if (selector === 'tbody tr' || selector === 'tr') return [gradeRow];
    return [];
  }}
}};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
const window = {{ document }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/student-portrait/getStdInfo') return response('unavailable', 503);
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-reordered-columns.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"], [{
            "course": "数据结构",
            "credits": 3,
            "point": 4,
            "score": 95,
            "category": "必修",
            "detail": "平时 40 / 期末 48",
        }])

    def test_education_script_reads_nested_direct_cells_from_component_grade_rows(self):
        script = self.embedded_script()
        harness = f"""
const nestedCell = value => ({{
  children: [{{}}, {{}}],
  innerText: value,
  textContent: value
}});
const gradeRow = {{
  children: [nestedCell('组件成绩'), nestedCell('3'), nestedCell('4.0'), nestedCell('95'), nestedCell('期末 95')],
  querySelectorAll: () => []
}};
const gradeTable = {{
  querySelectorAll: selector => {{
    if (selector === 'thead th') return [];
    if (selector === '.grade-row') return [gradeRow];
    return [];
  }}
}};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === '.grade-list' ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
const window = {{ document }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/student-portrait/getStdInfo') return response('unavailable', 503);
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-component-grade-row.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "组件成绩")
        self.assertEqual(result["grades"][0]["detail"], "期末 95")

    def test_education_script_finds_generic_grade_items_under_document_body(self):
        script = self.embedded_script()
        const_body = """
const cell = value => ({ innerText: value, textContent: value, children: [] });
const gradeRow = {
  children: [cell('通识英语'), cell('2'), cell('3.7'), cell('91'), cell('期末 91')],
  querySelectorAll: selector => selector === '.grade-item' ? [] : []
};
const body = {
  innerText: '学生成绩',
  children: [gradeRow],
  querySelectorAll: selector => selector === '.grade-item' ? [gradeRow] : []
};
const document = {
  body,
  querySelector: () => null,
  querySelectorAll: selector => selector === 'body' ? [body] : []
};
const window = { document };
globalThis.window = window;
globalThis.document = document;
globalThis.performance = { getEntriesByType: () => [] };
globalThis.fetch = async () => response('not found', 404);
function response(body, status = 200) {
  return { status, ok: status >= 200 && status < 300, text: async () => body };
}
"""
        harness = f"""
{const_body}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-body-grade-items.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "通识英语")

    def test_education_script_keeps_rendered_grade_table_when_grade_page_request_fails(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{ querySelectorAll: selector => selector === 'td' ? cells(['离线成绩', '2', '3.5', '88', '平时 40 / 期末 48']) : [] }};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' || selector === 'tr' ? [gradeRow] : [])
}};
globalThis.window = {{}};
globalThis.document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/grade/sheet/') throw new Error('grade page request unavailable');
  if (path === '/student/for-std/student-portrait/getStdInfo') return response(JSON.stringify({{ student: {{ id: 'student-fixture' }} }}));
  if (path.startsWith('/student/for-std/grade/sheet/info/')) return response('unavailable', 503);
  if (path === '/student/for-std/course-table') return response('<script>var semesters = [{{"id":"term-fixture","name":"2026 秋","startDate":"2026-08-31","endDate":"2027-01-10"}}];</script>');
  if (path === '/student/ws/semester/get/term-fixture') return response(JSON.stringify({{ id: 'term-fixture', name: '2026 秋', startDate: '2026-08-31', endDate: '2027-01-10' }}));
  if (path === '/student/for-std/course-table/semester/term-fixture/print-data/student-fixture') return response(JSON.stringify({{ studentTableVm: {{ activities: [] }} }}));
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-dom-fetch-fallback.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "离线成绩")

    def test_education_script_reads_same_origin_grade_table_inside_iframe(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{ querySelectorAll: selector => selector === 'td' ? cells(['iframe成绩', '3', '4.0', '95', '期末 95']) : [] }};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' || selector === 'tr' ? [gradeRow] : [])
}};
const frameDocument = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
const frameWindow = {{ document: frameDocument }};
const frame = {{ contentWindow: frameWindow, contentDocument: frameDocument }};
const topDocument = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'iframe' ? [frame] : [],
  body: {{ innerText: '成绩页面' }}
}};
const window = {{ studentId: 'student-fixture', document: topDocument }};
globalThis.window = window;
globalThis.document = topDocument;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/grade/sheet/') return response('<html><body>成绩页面</body></html>');
  if (path === '/student/for-std/student-portrait/getMyGpa') return response(JSON.stringify({{ gpa: 3.9 }}));
  if (path === '/student/for-std/course-table') return response('<script>var semesters = [{{"id":"term-fixture","name":"2026 秋","startDate":"2026-08-31","endDate":"2027-01-10"}}];</script>');
  if (path === '/student/ws/semester/get/term-fixture') return response(JSON.stringify({{ id: 'term-fixture', name: '2026 秋', startDate: '2026-08-31', endDate: '2027-01-10' }}));
  if (path === '/student/for-std/course-table/semester/term-fixture/print-data/student-fixture') return response(JSON.stringify({{ studentTableVm: {{ activities: [] }} }}));
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-iframe-fallback.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "iframe成绩")

    def test_education_script_waits_for_delayed_grade_table_rendering(self):
        script = self.embedded_script()
        harness = f"""
let rendered = false;
        // A slow SPA route can mount the table after the old 3.5 second poll
        // window. Keep this above that boundary so the native fallback cannot
        // regress to an empty grade collection.
        setTimeout(() => {{ rendered = true; }}, 4200);
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{ querySelectorAll: selector => selector === 'td' ? cells(['延迟成绩', '2', '3.2', '87', '期末 87']) : [] }};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' || selector === 'tr' ? [gradeRow] : [])
}};
const window = {{ studentId: 'student-fixture' }};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' && rendered ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/grade/sheet/') return response('<html><body>学生成绩</body></html>');
  if (path === '/student/for-std/student-portrait/getMyGpa') return response(JSON.stringify({{ gpa: 3.2 }}));
  if (path === '/student/for-std/course-table') return response('<script>var semesters = [{{"id":"term-fixture","name":"2026 秋","startDate":"2026-08-31","endDate":"2027-01-10"}}];</script>');
  if (path === '/student/ws/semester/get/term-fixture') return response(JSON.stringify({{ id: 'term-fixture', name: '2026 秋', startDate: '2026-08-31', endDate: '2027-01-10' }}));
  if (path === '/student/for-std/course-table/semester/term-fixture/print-data/student-fixture') return response(JSON.stringify({{ studentTableVm: {{ activities: [] }} }}));
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-delayed-table.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "延迟成绩")

    def test_education_script_resamples_rows_after_grade_request_when_spa_mounts_late(self):
        script = self.embedded_script()
        harness = f"""
let rendered = false;
// The first DOM poll ends at eight seconds. Mount while the fallback request
// is in flight to reproduce a slow Vue route on a real device.
setTimeout(() => {{ rendered = true; }}, 8200);
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{ querySelectorAll: selector => selector === 'td' ? cells(['请求期间成绩', '2', '3.5', '88', '期末 88']) : [] }};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' || selector === 'tr' ? [gradeRow] : [])
}};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' && rendered ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
const window = {{ document }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/grade/sheet/') {{
    await new Promise(resolve => setTimeout(resolve, 700));
    return response('<html><body>学生成绩</body></html>');
  }}
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-grade-late-request.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "请求期间成绩")

    def test_education_script_keeps_grades_when_schedule_endpoint_is_unavailable(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{ querySelectorAll: selector => selector === 'td' ? cells(['仅成绩', '2', '3.5', '88', '期末 88']) : [] }};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' || selector === 'tr' ? [gradeRow] : [])
}};
const window = {{ studentId: 'student-fixture' }};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/grade/sheet/') return response('<html><body>学生成绩</body></html>');
  if (path === '/student/for-std/course-table') throw new Error('schedule endpoint unavailable');
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-grade-only.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "仅成绩")
        self.assertEqual(result["schedule"]["semester"]["id"], "current")
        self.assertFalse(result["scheduleAvailable"])

    def test_education_script_returns_rendered_grades_without_student_bootstrap(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{ querySelectorAll: selector => selector === 'td' ? cells(['无学号成绩', '2', '3.1', '86', '期末 86']) : [] }};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' || selector === 'tr' ? [gradeRow] : [])
}};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' ? [gradeTable] : [],
  documentElement: {{ outerHTML: '<html><body>学生成绩</body></html>' }},
  body: {{ innerText: '学生成绩' }}
}};
const window = {{ document }};
let studentInfoCalls = 0;
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/student-portrait/getStdInfo') {{
    studentInfoCalls += 1;
    return response('unavailable', 503);
  }}
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(JSON.stringify({{ result: JSON.parse(value), studentInfoCalls }}))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-rendered-no-bootstrap.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        payload = json.loads(stdout)
        self.assertLessEqual(payload["studentInfoCalls"], 1)
        self.assertEqual(payload["result"]["phase"], "success")
        self.assertEqual(payload["result"]["grades"][0]["course"], "无学号成绩")
        self.assertFalse(payload["result"]["scheduleAvailable"])

    def test_education_script_reads_td_headers_and_component_data_attributes(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const headerRow = {{
  querySelectorAll: selector => selector === 'td'
    ? cells(['课程性质', '课程名称', '学分', '成绩', '绩点', '成绩构成'])
    : [],
  children: []
}};
const attributes = {{
  'data-course-name': '组件属性成绩',
  'data-credits': '3',
  'data-score': '92',
  'data-point': '3.8',
  'data-detail': '期末 92',
  'data-category': '必修'
}};
const gradeRow = {{
  getAttribute: name => Object.prototype.hasOwnProperty.call(attributes, name) ? attributes[name] : null,
  querySelectorAll: () => [],
  children: [],
  innerText: '组件属性成绩 3 92 3.8 期末 92'
}};
const gradeTable = {{
  querySelectorAll: selector => {{
    if (selector === 'tr') return [headerRow];
    if (selector === 'tr:first-child td') return cells(['课程性质', '课程名称', '学分', '成绩', '绩点', '成绩构成']);
    if (selector === '[data-course-name]') return [gradeRow];
    return [];
  }}
}};
const option = {{ textContent: '2026 秋', value: 'term-fixture', selected: true }};
const body = {{
  innerText: '学生成绩',
  querySelectorAll: selector => selector === '[data-course-name]' ? [gradeRow] : []
}};
const document = {{
  body,
  querySelector: () => null,
  querySelectorAll: selector => {{
    if (selector === 'table') return [gradeTable];
    if (selector === 'select option') return [option];
    if (selector === 'body') return [body];
    return [];
  }}
}};
const window = {{ document }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async () => response('not found', 404);
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-component-data-attributes.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"], [{
            "course": "组件属性成绩",
            "credits": 3,
            "point": 3.8,
            "score": 92,
            "category": "必修",
            "detail": "期末 92",
        }])

    def test_education_script_maps_semantic_cell_labels_without_a_header_row(self):
        script = self.embedded_script()
        harness = f"""
const semanticCell = (label, value) => ({{
  getAttribute: name => (name === 'data-label' || name === 'aria-label' || name === 'data-field') ? label : null,
  innerText: value,
  textContent: value,
  children: []
}});
const gradeRow = {{
  querySelectorAll: selector => selector === 'td' ? [
    semanticCell('成绩', '91'),
    semanticCell('课程名称', '语义列成绩'),
    semanticCell('成绩构成', '期末 91'),
    semanticCell('绩点', '3.7'),
    semanticCell('课程性质', '专业必修'),
    semanticCell('学分', '2')
  ] : [],
  children: []
}};
const gradeTable = {{
  querySelectorAll: selector => selector === '[data-grade-row]' ? [gradeRow] : []
}};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === '[role="table"]' ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
const window = {{ document }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async () => response('not found', 404);
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-semantic-cell-labels.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"], [{
            "course": "语义列成绩",
            "credits": 2,
            "point": 3.7,
            "score": 91,
            "category": "专业必修",
            "detail": "期末 91",
        }])

    def test_education_script_reads_rendered_grade_cards(self):
        script = self.embedded_script()
        harness = f"""
const courseName = {{ className: 'course-name', innerText: '大学英语（III）', textContent: '大学英语（III）', children: [], querySelectorAll: () => [] }};
const card = {{
  className: 'score-item',
  innerText: '大学英语（III）\\n课程 · 2.0 学分\\n绩点 2.7\\n期末成绩:64.2 平时成绩:85.7\\n成绩 75',
  textContent: '大学英语（III） 课程 2.0 学分 绩点 2.7 期末成绩:64.2 平时成绩:85.7 成绩 75',
  children: [courseName],
  querySelectorAll: selector => selector === '.course-name' ? [courseName] : []
}};
const body = {{
  innerText: '学生成绩',
  querySelectorAll: selector => selector === '.score-item' ? [card] : []
}};
const document = {{
  body,
  querySelector: () => null,
  querySelectorAll: selector => selector === 'body' ? [body] : []
}};
const window = {{ document }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async () => response('not found', 404);
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-grade-card.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"], [{
            "course": "大学英语（III）",
            "credits": 2,
            "point": 2.7,
            "score": 75,
            "category": "课程",
            "detail": "",
        }])

    def test_education_script_extracts_course_from_single_line_mobile_card_without_title_class(self):
        """The real mobile card can expose one flattened innerText string."""
        script = self.embedded_script()
        harness = f"""
const card = {{
  className: 'score-item',
  // WebKit may flatten block text when the card is rendered by a component
  // wrapper. There is no stable course-name class in this variant.
  innerText: '大学英语（III） 课程 · 2.0 学分 绩点 2.7 期末成绩:64.2 平时成绩:85.7 成绩 75',
  textContent: '大学英语（III） 课程 · 2.0 学分 绩点 2.7 期末成绩:64.2 平时成绩:85.7 成绩 75',
  children: [],
  querySelectorAll: () => []
}};
const body = {{
  innerText: '学生成绩',
  querySelectorAll: selector => selector === '.score-item' ? [card] : []
}};
const document = {{
  body,
  querySelector: () => null,
  querySelectorAll: selector => selector === 'body' ? [body] : []
}};
const window = {{ document }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async () => response('not found', 404);
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-grade-card-flat-text.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"], [{
            "course": "大学英语（III）",
            "credits": 2,
            "point": 2.7,
            "score": 75,
            "category": "课程",
            "detail": "",
        }])

    def test_education_script_collects_delayed_rows_while_route_is_still_home(self):
        script = self.embedded_script()
        harness = f"""
let rendered = false;
setTimeout(() => {{ rendered = true; }}, 1200);
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{
  querySelectorAll: selector => selector === 'td' ? cells(['首页延迟成绩', '1', '3.0', '82', '期末 82']) : [],
  children: []
}};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' ? [gradeRow] : [])
}};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' && rendered ? [gradeTable] : [],
  body: {{ innerText: '首页' }}
}};
const window = {{ document }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async () => response('not found', 404);
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-home-delayed-table.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "首页延迟成绩")


if __name__ == "__main__":
    unittest.main()
