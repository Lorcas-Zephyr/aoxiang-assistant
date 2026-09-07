import importlib.util
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "validate_pr_contract.py"
MODULE_SPEC = importlib.util.spec_from_file_location("validate_pr_contract", SCRIPT_PATH)
validator_module = importlib.util.module_from_spec(MODULE_SPEC)
sys.modules[MODULE_SPEC.name] = validator_module
if MODULE_SPEC.loader is not None:
    MODULE_SPEC.loader.exec_module(validator_module)


class PullRequestContractValidatorTest(unittest.TestCase):
    def test_platform_only_pr_with_complete_declarations_is_valid(self):
        errors = validator_module.validate_body(self.body("platform"))

        self.assertEqual([], errors)

    def test_requires_exactly_one_change_classification(self):
        none_selected = self.body("none")
        two_selected = self.body("platform").replace(
            "- [ ] Shared behavior:", "- [x] Shared behavior:"
        )

        self.assertContains(
            validator_module.validate_body(none_selected),
            "exactly one",
        )
        self.assertContains(
            validator_module.validate_body(two_selected),
            "exactly one",
        )

    def test_shared_behavior_requires_fixture_and_independent_expected_evidence(self):
        body = self.body("shared").replace(
            "- [x] I added or updated a sanitized golden fixture",
            "- [ ] I added or updated a sanitized golden fixture",
        )

        errors = validator_module.validate_body(body)

        self.assertContains(errors, "sanitized golden fixture")

    def test_breaking_change_requires_version_and_migration_evidence(self):
        body = self.body("breaking").replace(
            "New `schemaVersion` / `golden/vN` for a breaking change: schemaVersion: 2; golden/v2",
            "New `schemaVersion` / `golden/vN` for a breaking change: not applicable",
        ).replace(
            "- [x] For a wire/contract breaking change",
            "- [ ] For a wire/contract breaking change",
        )

        errors = validator_module.validate_body(body)

        self.assertContains(errors, "schemaVersion")
        self.assertContains(errors, "migration")

    def test_contract_sensitive_files_cannot_be_declared_platform_only(self):
        errors = validator_module.validate_body(
            self.body("platform"),
            changed_files=["contract-fixtures/golden/v1/manifest.json"],
        )

        self.assertContains(errors, "contract-sensitive")

    def test_swift_capability_resources_cannot_be_declared_platform_only(self):
        errors = validator_module.validate_body(
            self.body("platform"),
            changed_files=["ios/AoxiangCore/Package.swift"],
        )

        self.assertContains(errors, "contract-sensitive")

    def test_shared_behavior_requires_actual_fixture_and_expected_changes(self):
        errors = validator_module.validate_body(
            self.body("shared"),
            changed_files=["app/src/main/java/cn/nwpu/campus/PortalApiParsers.java"],
        )

        self.assertContains(errors, "contract-fixtures")
        self.assertContains(errors, "expected.json")

        errors = validator_module.validate_body(
            self.body("shared"),
            changed_files=["contract-fixtures/golden/v1/grades-api-response/input.json"],
        )
        self.assertContains(errors, "expected.json")

        self.assertEqual(
            [],
            validator_module.validate_body(
                self.body("shared"),
                changed_files=[
                    "app/src/main/java/cn/nwpu/campus/PortalApiParsers.java",
                    "contract-fixtures/golden/v1/grades-api-response/input.json",
                    "contract-fixtures/golden/v1/grades-api-response/expected.json",
                ],
            ),
        )

    def test_shared_grade_record_and_auth_seams_cannot_be_declared_platform_only(self):
        for path in (
            "app/src/main/java/cn/nwpu/campus/GradeRecord.java",
            "app/src/main/java/cn/nwpu/campus/AuthenticationPolicy.java",
            "app/src/main/java/cn/nwpu/campus/UnifiedAuthTracker.java",
        ):
            with self.subTest(path=path):
                errors = validator_module.validate_body(
                    self.body("platform"),
                    changed_files=[path],
                )
                self.assertContains(errors, "contract-sensitive")

    def test_requires_security_declarations_and_validation_notes(self):
        body = self.body("platform").replace(
            "- [x] No password, Cookie, token, `Authorization` header",
            "- [ ] No password, Cookie, token, `Authorization` header",
        ).replace(
            "Validated locally and rollback is git revert.",
            "<!-- Include commands, fixture IDs, migration versions, known limitations, and a rollback plan. -->",
        )

        errors = validator_module.validate_body(body)

        self.assertContains(errors, "security")
        self.assertContains(errors, "validation notes")

    @staticmethod
    def body(classification):
        checks = {
            "none": (" ", " ", " "),
            "platform": ("x", " ", " "),
            "shared": (" ", "x", " "),
            "breaking": (" ", " ", "x"),
        }[classification]
        shared_evidence = "x" if classification in {"shared", "breaking"} else " "
        breaking_evidence = "x" if classification == "breaking" else " "
        return f"""## Change classification

- [{checks[0]}] Platform-only: Android or iOS implementation/UI behavior with no shared contract change
- [{checks[1]}] Shared behavior: parsing, normalization, scheduling, diffing, persistence semantics, or another Android/iOS behavior change
- [{checks[2]}] Wire/contract breaking: incompatible JSON/API/enum/ID/date-time change, or a migration that cannot read the previous contract

## Contract and compatibility

- Baseline or contract version affected: `v2.2.2` / `golden/v1`
- Does this change alter observable Android/iOS behavior? no; infrastructure only
- Does this change alter exported JSON or a wire/API interpretation? no
- New `schemaVersion` / `golden/vN` for a breaking change: schemaVersion: 2; golden/v2
- Rollback or downgrade behavior: revert the commit; stored data is unchanged

## Required evidence

- [{shared_evidence}] I added or updated a sanitized golden fixture when shared behavior changed.
- [{shared_evidence}] `expected.json` was reviewed independently from the implementation output.
- [{breaking_evidence}] For a wire/contract breaking change, I increased `schemaVersion`, created a new `golden/vN`, retained the previous fixtures, and added migration tests.
- [x] I ran the Android contract tests and recorded the result.
- [x] I ran the Swift contract tests; no pending adapter is described as behavior-compatible.
- [x] I updated the changelog/release notes when user-visible behavior changed.
- [x] I documented any intentional Android/iOS output difference.

## Security and privacy

- [x] No password, Cookie, token, `Authorization` header, SMS verification code, session data, or real personal/dormitory identifier was added to source, fixtures, logs, screenshots, or test output.
- [x] All fixture inputs are sanitized and synthetic or otherwise approved for repository storage.
- [x] I checked that failure output does not print credentials or WebView session data.

## Validation notes

Validated locally and rollback is git revert.
"""

    def assertContains(self, errors, fragment):
        self.assertTrue(
            any(fragment.lower() in error.lower() for error in errors),
            "\n".join(errors),
        )


if __name__ == "__main__":
    unittest.main()
