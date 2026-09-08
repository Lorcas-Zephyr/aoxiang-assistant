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

    def test_embedded_electricity_script_is_javascript_syntax_valid_and_supports_portal_variants(self):
        self.assert_embedded_script_is_syntax_valid(
            r'private static let electricityBalanceScript = \"\"\"(.*?)\"\"\"',
            "visible-electricity-collection",
        )
        source = SOURCE_FILE.read_text(encoding="utf-8")
        self.assertIn("app.__vueParentComponent", source)
        self.assertIn("Object.entries(value)", source)
        self.assertIn("scheduleElectricityEvaluation", source)


if __name__ == "__main__":
    unittest.main()
