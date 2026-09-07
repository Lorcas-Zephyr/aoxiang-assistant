#!/usr/bin/env python3
"""Fail closed when a pull request omits cross-platform contract evidence."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Iterable


CLASSIFICATIONS = {
    "platform": "Platform-only:",
    "shared": "Shared behavior:",
    "breaking": "Wire/contract breaking:",
}
CONTRACT_SENSITIVE_PREFIXES = (
    "contract-fixtures/",
    "ios/AoxiangCore/",
    ".github/workflows/cross-platform-contract.yml",
    ".github/workflows/pr-contract-gate.yml",
    ".github/pull_request_template.md",
    "scripts/validate_golden_fixtures.py",
    "scripts/validate_pr_contract.py",
    "scripts/tests/",
    "docs/CROSS_PLATFORM_SYNC.md",
    "docs/GOLDEN_FIXTURES.md",
    "docs/LOCAL_DATA_CONTRACT.md",
    "app/src/main/java/cn/nwpu/campus/BackupContract.java",
    "app/src/main/java/cn/nwpu/campus/LocalDataContract.java",
    "app/src/main/java/cn/nwpu/campus/GradeRecord.java",
    "app/src/main/java/cn/nwpu/campus/AuthenticationPolicy.java",
    "app/src/main/java/cn/nwpu/campus/UnifiedAuthTracker.java",
    "app/src/main/java/cn/nwpu/campus/PortalApiParsers.java",
    "app/src/main/java/cn/nwpu/campus/ScheduleImport.java",
    "app/src/main/java/cn/nwpu/campus/ScheduleUtils.java",
    "app/src/main/java/cn/nwpu/campus/SyncTimePolicy.java",
    "app/src/main/java/cn/nwpu/campus/UpdateDiff.java",
)
FIXTURE_EVIDENCE = (
    "I added or updated a sanitized golden fixture",
    "`expected.json` was reviewed independently",
)
FIXTURE_ROOT = "contract-fixtures/"
BREAKING_EVIDENCE = (
    "For a wire/contract breaking change",
)
SECURITY_EVIDENCE = (
    "No password, Cookie, token, `Authorization` header",
    "All fixture inputs are sanitized",
    "I checked that failure output does not print credentials",
)
PLACEHOLDER_MARKERS = ("<!--", "fill in", "yes/no", "not applicable")


def checked(body: str, label: str) -> bool:
    pattern = re.compile(rf"^- \[[xX]\]\s+{re.escape(label)}", re.MULTILINE)
    return pattern.search(body) is not None


def selected_classifications(body: str) -> list[str]:
    return [key for key, label in CLASSIFICATIONS.items() if checked(body, label)]


def field_value(body: str, label: str) -> str:
    pattern = re.compile(
        rf"^-\s+{re.escape(label)}\s*(.+)$",
        re.MULTILINE | re.IGNORECASE,
    )
    match = pattern.search(body)
    return match.group(1).strip() if match else ""


def has_real_value(value: str) -> bool:
    lower = value.lower()
    return bool(value) and not any(marker in lower for marker in PLACEHOLDER_MARKERS)


def contract_sensitive(path: str) -> bool:
    normalized = path.replace("\\", "/").lstrip("./")
    return any(normalized.startswith(prefix) for prefix in CONTRACT_SENSITIVE_PREFIXES)


def normalized_changed_files(changed_files: Iterable[str]) -> list[str]:
    return [path.replace("\\", "/").lstrip("./") for path in changed_files]


def validate_body(body: str, changed_files: Iterable[str] = ()) -> list[str]:
    errors: list[str] = []
    selected = selected_classifications(body)
    if len(selected) != 1:
        errors.append("Select exactly one change classification in the PR template")
        classification = None
    else:
        classification = selected[0]

    changed_paths = normalized_changed_files(changed_files)
    sensitive_files = sorted(path for path in changed_paths if contract_sensitive(path))
    if classification == "platform" and sensitive_files:
        errors.append(
            "Platform-only cannot modify contract-sensitive files: "
            + ", ".join(sensitive_files)
        )

    if classification in {"shared", "breaking"}:
        for label in FIXTURE_EVIDENCE:
            if not checked(body, label):
                errors.append(f"Shared behavior requires checked evidence: {label}")
        if changed_paths:
            fixture_paths = [
                path for path in changed_paths if path.startswith(FIXTURE_ROOT)
            ]
            if not fixture_paths:
                errors.append(
                    "Shared behavior must modify at least one file under contract-fixtures/"
                )
            if not any(path.endswith("/expected.json") for path in fixture_paths):
                errors.append(
                    "Shared behavior must modify an independent expected.json fixture"
                )

    if classification == "breaking":
        version_value = field_value(
            body,
            "New `schemaVersion` / `golden/vN` for a breaking change:",
        )
        if (
            not has_real_value(version_value)
            or "schemaversion" not in version_value.lower()
            or not re.search(r"golden/v[1-9][0-9]*", version_value, re.IGNORECASE)
        ):
            errors.append(
                "Breaking changes must name the new schemaVersion and golden/vN"
            )
        for label in BREAKING_EVIDENCE:
            if not checked(body, label):
                errors.append(f"Breaking changes require checked migration evidence: {label}")

    for label in SECURITY_EVIDENCE:
        if not checked(body, label):
            errors.append(f"Required security declaration is unchecked: {label}")

    notes_match = re.search(
        r"^## Validation notes\s*$([\s\S]*)",
        body,
        re.MULTILINE | re.IGNORECASE,
    )
    notes = notes_match.group(1).strip() if notes_match else ""
    if not has_real_value(notes):
        errors.append("Validation notes must contain commands, limitations, and rollback details")

    return errors


def event_payload(path: Path) -> tuple[str, list[str]]:
    event = json.loads(path.read_text(encoding="utf-8"))
    pull_request = event.get("pull_request") or {}
    body = pull_request.get("body") or ""
    files = event.get("changed_files") or []
    return body, [str(item) for item in files]


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--body-file", type=Path)
    parser.add_argument("--event-file", type=Path)
    parser.add_argument("--changed-files-file", type=Path)
    args = parser.parse_args(argv)

    if args.event_file:
        body, changed_files = event_payload(args.event_file)
    elif args.body_file:
        body = args.body_file.read_text(encoding="utf-8")
        changed_files = []
    else:
        parser.error("provide --event-file or --body-file")

    if args.changed_files_file:
        changed_files = [
            line.strip()
            for line in args.changed_files_file.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    errors = validate_body(body, changed_files)
    if errors:
        print("Pull request contract validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("Pull request contract declaration is complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
