import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_ROOT = REPO_ROOT / ".github" / "workflows"
USES_PATTERN = re.compile(r"^\s*(?:-\s*)?uses:\s*(?P<action>[^\s@]+)@(?P<ref>[^\s#]+)")
SHA_PATTERN = re.compile(r"^[0-9a-fA-F]{40}$")


class WorkflowDependencyPinTest(unittest.TestCase):
    def test_third_party_workflow_actions_are_pinned_to_commit_shas(self):
        workflow_files = sorted(WORKFLOW_ROOT.glob("*.y*ml"))
        self.assertTrue(workflow_files, "expected at least one GitHub workflow")

        seen_actions = 0
        for workflow in workflow_files:
            for line_number, line in enumerate(
                workflow.read_text(encoding="utf-8").splitlines(), start=1
            ):
                match = USES_PATTERN.match(line)
                if match is None or match.group("action").startswith("./"):
                    continue
                seen_actions += 1
                self.assertRegex(
                    match.group("ref"),
                    SHA_PATTERN,
                    f"{workflow}:{line_number} must pin {match.group('action')} to a 40-char commit SHA",
                )
        self.assertGreater(seen_actions, 0, "expected workflow action dependencies")

    def test_pr_contract_gate_runs_trusted_base_workflow(self):
        trusted_workflow = WORKFLOW_ROOT / "pr-contract-gate.yml"
        self.assertTrue(trusted_workflow.is_file(), "trusted PR gate workflow is required")
        content = trusted_workflow.read_text(encoding="utf-8")
        self.assertIn("pull_request_target:", content)
        self.assertIn("github.event.pull_request.base.sha", content)
        self.assertIn("scripts/validate_pr_contract.py", content)
        self.assertNotIn("github.event.pull_request.head.sha", content)

    def test_re_signable_ipa_workflow_uses_an_explicit_source_ref(self):
        workflow = WORKFLOW_ROOT / "ios-re-signable-ipa.yml"
        self.assertTrue(workflow.is_file(), "re-signable IPA workflow is required")
        content = workflow.read_text(encoding="utf-8")
        self.assertIn("source_ref:", content)
        self.assertIn("default: iOS", content)
        self.assertIn("ref: ${{ inputs.source_ref }}", content)

    def test_re_signable_ipa_workflow_verifies_sideload_and_widget_variants(self):
        content = (WORKFLOW_ROOT / "ios-re-signable-ipa.yml").read_text(encoding="utf-8")
        self.assertIn("AoxiangAssistant-sideload-re-signable.ipa", content)
        self.assertIn("AoxiangAssistant-full-widget-re-signable.ipa", content)
        self.assertIn("PlugIns/AoxiangAssistantWidget.appex/Info.plist", content)


if __name__ == "__main__":
    unittest.main()
