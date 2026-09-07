import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "validate_golden_fixtures.py"
MODULE_SPEC = importlib.util.spec_from_file_location("validate_golden_fixtures", SCRIPT_PATH)
validator_module = importlib.util.module_from_spec(MODULE_SPEC)
sys.modules[MODULE_SPEC.name] = validator_module
if MODULE_SPEC.loader is not None:
    MODULE_SPEC.loader.exec_module(validator_module)


class GoldenFixtureValidatorTest(unittest.TestCase):
    def test_repository_fixture_suite_is_valid(self):
        result = validator_module.validate(REPO_ROOT / "contract-fixtures" / "golden" / "v1")
        self.assertTrue(result.ok, result.format_errors())

    def test_default_cli_validates_the_complete_corpus(self):
        import subprocess

        completed = subprocess.run(
            [sys.executable, str(SCRIPT_PATH)],
            cwd=tempfile.gettempdir(),
            capture_output=True,
            text=True,
        )

        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("1 golden fixture version(s)", completed.stdout)

    def test_corpus_validation_discovers_and_validates_every_version(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            golden_root = Path(temporary_directory) / "golden"
            v1 = golden_root / "v1"
            v2 = golden_root / "v2"
            shutil.copytree(REPO_ROOT / "contract-fixtures" / "golden" / "v1", v1)
            shutil.copytree(v1, v2)
            manifest = self.read_manifest(v2)
            manifest["schemaVersion"] = 2
            self.write_manifest(v2, manifest)

            result = validator_module.validate_corpus(golden_root)

            self.assertTrue(result.ok, result.format_errors())
            self.assertEqual(result.version_count, 2)
            self.assertEqual(result.scenario_count, 30)

    def test_future_version_allows_new_stable_kind_without_changing_v1_registry(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            version_root = Path(temporary_directory) / "v2"
            shutil.copytree(REPO_ROOT / "contract-fixtures" / "golden" / "v1", version_root)
            manifest = self.read_manifest(version_root)
            manifest["schemaVersion"] = 2
            manifest["scenarios"][0]["id"] = "grades-api-response-v2"
            manifest["scenarios"][0]["kind"] = "grades-api-normalized-v2"
            self.write_manifest(version_root, manifest)

            result = validator_module.validate(version_root)

            self.assertTrue(result.ok, result.format_errors())

    def test_future_version_rejects_noncanonical_kind(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            version_root = Path(temporary_directory) / "v2"
            shutil.copytree(REPO_ROOT / "contract-fixtures" / "golden" / "v1", version_root)
            manifest = self.read_manifest(version_root)
            manifest["schemaVersion"] = 2
            manifest["scenarios"][0]["id"] = "grades-api-response-v2"
            manifest["scenarios"][0]["kind"] = "Grades_API"
            self.write_manifest(version_root, manifest)

            result = validator_module.validate(version_root)

            self.assertContains(result, "stable kebab-case")

    def test_corpus_validation_rejects_version_gaps_and_unversioned_directories(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            golden_root = Path(temporary_directory) / "golden"
            shutil.copytree(REPO_ROOT / "contract-fixtures" / "golden" / "v1", golden_root / "v1")
            shutil.copytree(golden_root / "v1", golden_root / "v3")
            (golden_root / "draft").mkdir()

            result = validator_module.validate_corpus(golden_root)

            self.assertContains(result, "contiguous")
            self.assertContains(result, "unexpected directory")

    def test_version_manifest_must_match_its_directory(self):
        with self.fixture_copy() as root:
            root.rename(root.parent / "v2")
            version_two = root.parent / "v2"

            result = validator_module.validate(version_two)

            self.assertContains(result, "schemaVersion must be integer 2")

    def test_rejects_manifest_path_traversal(self):
        with self.fixture_copy() as root:
            manifest = self.read_manifest(root)
            manifest["scenarios"][0]["input"] = "../outside.json"
            self.write_manifest(root, manifest)
            result = validator_module.validate(root)
            self.assertContains(result, "must stay within fixture root")

    def test_rejects_absolute_and_noncanonical_manifest_paths(self):
        invalid_paths = ("/absolute/input.json", "C:/absolute/input.json", "./input.json", "a//input.json")
        for invalid_path in invalid_paths:
            with self.subTest(path=invalid_path), self.fixture_copy() as root:
                manifest = self.read_manifest(root)
                manifest["scenarios"][0]["input"] = invalid_path
                self.write_manifest(root, manifest)
                result = validator_module.validate(root)
                self.assertContains(result, "fixture path")

    def test_rejects_duplicate_manifest_references(self):
        with self.fixture_copy() as root:
            manifest = self.read_manifest(root)
            manifest["scenarios"][1]["input"] = manifest["scenarios"][0]["input"]
            self.write_manifest(root, manifest)
            result = validator_module.validate(root)
            self.assertContains(result, "referenced more than once")

    def test_rejects_input_expected_only_key(self):
        with self.fixture_copy() as root:
            path = root / "grades-api-response" / "input.json"
            document = json.loads(path.read_text(encoding="utf-8"))
            document["selectedGpa"] = 3.14
            path.write_text(json.dumps(document), encoding="utf-8")
            result = validator_module.validate(root)
            self.assertContains(result, "expected-only key")

    def test_rejects_sensitive_value_in_html(self):
        with self.fixture_copy() as root:
            path = root / "grades-component-html" / "detail.html"
            path.write_text('<input type="password" value="not-a-fixture-secret">', encoding="utf-8")
            result = validator_module.validate(root)
            self.assertContains(result, "sensitive content")

    def test_rejects_unreferenced_file(self):
        with self.fixture_copy() as root:
            (root / "schedule-empty" / "orphan.json").write_text("{}", encoding="utf-8")
            result = validator_module.validate(root)
            self.assertContains(result, "not referenced by manifest")

    def test_rejects_duplicate_json_keys(self):
        with self.fixture_copy() as root:
            (root / "schedule-empty" / "input.json").write_text(
                '{"semester": {}, "semester": {}}', encoding="utf-8"
            )
            result = validator_module.validate(root)
            self.assertContains(result, "duplicate JSON key")

    def test_rejects_null_json_root(self):
        with self.fixture_copy() as root:
            (root / "schedule-empty" / "input.json").write_text("null", encoding="utf-8")
            result = validator_module.validate(root)
            self.assertContains(result, "JSON root must be an object or array")

    def test_reports_unhashable_kind_instead_of_crashing(self):
        with self.fixture_copy() as root:
            manifest = self.read_manifest(root)
            manifest["scenarios"][0]["kind"] = ["grades-api"]
            self.write_manifest(root, manifest)
            result = validator_module.validate(root)
            self.assertContains(result, "kind is unsupported")

    def test_rejects_invalid_utf8(self):
        with self.fixture_copy() as root:
            (root / "schedule-empty" / "input.json").write_bytes(b'{"bad":"\xff"}')
            result = validator_module.validate(root)
            self.assertContains(result, "not valid UTF-8")

    def test_rejects_invalid_manifest_contract_fields(self):
        mutations = {
            "schemaVersion": 2,
            "suite": "another-suite",
            "businessTimeZone": "UTC",
        }
        for field, value in mutations.items():
            with self.subTest(field=field), self.fixture_copy() as root:
                manifest = self.read_manifest(root)
                manifest[field] = value
                self.write_manifest(root, manifest)
                result = validator_module.validate(root)
                self.assertContains(result, f"manifest.{field}")

    def test_rejects_wrong_kind_for_known_scenario(self):
        with self.fixture_copy() as root:
            manifest = self.read_manifest(root)
            manifest["scenarios"][0]["kind"] = "schedule-empty"
            self.write_manifest(root, manifest)
            result = validator_module.validate(root)
            self.assertContains(result, "must use kind")

    def test_rejects_nonstandard_json_number(self):
        with self.fixture_copy() as root:
            (root / "schedule-empty" / "input.json").write_text(
                '{"nonPortableNumber": NaN}', encoding="utf-8"
            )
            result = validator_module.validate(root)
            self.assertContains(result, "not valid JSON")

    def test_rejects_sensitive_json_key_and_header_value(self):
        mutations = (
            {"password": "redacted"},
            {"header": "Authorization: Bearer redacted"},
            {"header": "Cookie: JSESSIONID=redacted"},
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation), self.fixture_copy() as root:
                path = root / "schedule-empty" / "input.json"
                path.write_text(json.dumps(mutation), encoding="utf-8")
                result = validator_module.validate(root)
                self.assertContains(result, "sensitive")

    def test_cli_returns_distinct_validation_and_usage_exit_codes(self):
        import subprocess

        with self.fixture_copy() as root:
            (root / "orphan.json").write_text("{}", encoding="utf-8")
            invalid = subprocess.run(
                [sys.executable, str(SCRIPT_PATH), str(root)],
                capture_output=True,
                text=True,
            )
        missing = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), str(REPO_ROOT / "does-not-exist")],
            capture_output=True,
            text=True,
        )
        self.assertEqual(invalid.returncode, 1, invalid.stdout + invalid.stderr)
        self.assertEqual(missing.returncode, 2, missing.stdout + missing.stderr)

    def test_cli_works_from_an_unrelated_working_directory(self):
        # This is intentionally a subprocess test once the script exposes its CLI.
        import subprocess
        completed = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), str(REPO_ROOT / "contract-fixtures" / "golden" / "v1")],
            cwd=tempfile.gettempdir(),
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("validated", completed.stdout.lower())

    def fixture_copy(self):
        temporary_directory = tempfile.TemporaryDirectory()
        target = Path(temporary_directory.name) / "v1"
        shutil.copytree(REPO_ROOT / "contract-fixtures" / "golden" / "v1", target)
        context = self._temporary_fixture_context(temporary_directory, target)
        return context

    @staticmethod
    def _temporary_fixture_context(temporary_directory, target):
        class FixtureContext:
            def __enter__(self):
                return target

            def __exit__(self, exc_type, exc_value, traceback):
                temporary_directory.cleanup()

        return FixtureContext()

    @staticmethod
    def read_manifest(root):
        return json.loads((root / "manifest.json").read_text(encoding="utf-8"))

    @staticmethod
    def write_manifest(root, manifest):
        (root / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    def assertContains(self, result, fragment):
        self.assertFalse(result.ok, result.format_errors())
        self.assertTrue(
            any(fragment.lower() in error.lower() for error in result.errors),
            result.format_errors(),
        )


if __name__ == "__main__":
    unittest.main()
