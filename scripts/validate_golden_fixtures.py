#!/usr/bin/env python3
"""Validate the shared Android/iOS golden fixture corpus without platform tooling."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any, Iterable


EXPECTED_SUITE = "aoxiang-assistant.golden"
EXPECTED_TIME_ZONE = "Asia/Shanghai"
EXPECTED_SCENARIO_KINDS = {
    "grades-api-response": "grades-api",
    "grades-component-html": "grades-component-html",
    "grades-gpa-portrait-fallback": "grades-portrait-fallback",
    "grades-retake-same-name": "grades-retake",
    "schedule-empty": "schedule-empty",
    "schedule-mixed-repeat": "schedule-repeat-rules",
    "schedule-non-contiguous": "schedule-non-contiguous-weeks",
    "schedule-friendship-summer": "schedule-friendship-summer",
    "schedule-friendship-winter": "schedule-friendship-winter",
    "schedule-teachers-locations": "schedule-teachers-locations",
    "schedule-online-filter": "schedule-online-filter",
    "electricity-settlement": "electricity-settlement",
    "electricity-anomaly": "electricity-anomaly",
    "auth-states": "authentication-states",
    "update-diff-notifications": "update-diff-notifications",
}
EXPECTED_SCENARIO_RESOURCE_FIELDS = {
    "grades-component-html": {"html"},
    "grades-gpa-portrait-fallback": {"html"},
}
EXPECTED_SCENARIOS = set(EXPECTED_SCENARIO_KINDS)
SUPPORTED_KINDS = set(EXPECTED_SCENARIO_KINDS.values())
FORBIDDEN_KEY_FRAGMENTS = {
    "password",
    "cookie",
    "token",
    "account",
    "studentid",
    "studentno",
    "captcha",
    "smscode",
    "verificationcode",
    "authorization",
    "setcookie",
    "session",
    "secret",
}
EXPECTED_ONLY_KEYS = {
    "expected",
    "settlement",
    "deferexpected",
    "overdueexpected",
    "authexited",
    "credentialsvalid",
    "interactivelogin",
    "explicitcredentialerror",
    "gradechangednames",
    "schedulechangednames",
    "gradenotification",
    "schedulenotification",
    "selectedgpa",
}
ALLOWED_VALUE_TOKENS = {"sessionexpired"}
ALLOWED_ROOT_FILES = {"README.md", "manifest.json"}
ALLOWED_FIXTURE_SUFFIXES = {".json", ".html"}
MANIFEST_FIELDS = {"schemaVersion", "suite", "businessTimeZone", "scenarios"}
SCENARIO_FIELDS = {"id", "kind", "input", "expected", "html"}
NORMALIZED_TOKEN_PATTERN = re.compile(r"[^A-Za-z0-9\u4e00-\u9fa5]")
VERSION_DIRECTORY_PATTERN = re.compile(r"^v([1-9][0-9]*)$")
STABLE_KEBAB_CASE_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class DuplicateJsonKey(ValueError):
    pass


class NonStandardJsonNumber(ValueError):
    pass


class InvalidJsonDocument:
    pass


INVALID_JSON = InvalidJsonDocument()


@dataclass(frozen=True)
class ValidationResult:
    root: Path
    scenario_count: int
    file_count: int
    errors: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return not self.errors

    def format_errors(self) -> str:
        return "\n".join(f"- {error}" for error in self.errors)


@dataclass(frozen=True)
class CorpusValidationResult:
    root: Path
    version_count: int
    scenario_count: int
    file_count: int
    errors: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return not self.errors

    def format_errors(self) -> str:
        return "\n".join(f"- {error}" for error in self.errors)


def normalize_token(value: str) -> str:
    return NORMALIZED_TOKEN_PATTERN.sub("", value).lower()


def duplicate_key_guard(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateJsonKey(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def reject_nonstandard_json_number(value: str) -> None:
    raise NonStandardJsonNumber(f"non-standard JSON number: {value}")


def read_utf8(path: Path, errors: list[str]) -> str | None:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        errors.append(f"cannot read {path}: {exc}")
        return None
    try:
        return raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        errors.append(f"{path} is not valid UTF-8: {exc}")
        return None


def read_json(path: Path, errors: list[str]) -> Any:
    text = read_utf8(path, errors)
    if text is None:
        return INVALID_JSON
    try:
        return json.loads(
            text,
            object_pairs_hook=duplicate_key_guard,
            parse_constant=reject_nonstandard_json_number,
        )
    except DuplicateJsonKey as exc:
        errors.append(f"{path}: {exc}")
    except json.JSONDecodeError as exc:
        errors.append(f"{path} is not valid JSON: {exc.msg} at line {exc.lineno}, column {exc.colno}")
    except NonStandardJsonNumber as exc:
        errors.append(f"{path} is not valid JSON: {exc}")
    return INVALID_JSON


def check_sensitive_json(value: Any, location: str, errors: list[str]) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = normalize_token(str(key))
            fragment = next((item for item in FORBIDDEN_KEY_FRAGMENTS if item in normalized), None)
            if fragment:
                errors.append(f"{location}: forbidden sensitive key {key!r} ({fragment})")
            check_sensitive_json(child, f"{location}.{key}", errors)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            check_sensitive_json(child, f"{location}[{index}]", errors)
    elif isinstance(value, str):
        normalized = normalize_token(value)
        if normalized in ALLOWED_VALUE_TOKENS:
            return
        lower = value.lower()
        header_pattern = re.compile(r"(?:^|\s)(?:authorization|cookie|set-cookie)\s*:")
        if (
            "authorizationbearer" in normalized
            or "setcookie" in normalized
            or header_pattern.search(lower)
        ):
            errors.append(f"{location}: forbidden sensitive value/content")


def check_expected_only_keys(value: Any, location: str, errors: list[str]) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in EXPECTED_ONLY_KEYS:
                errors.append(f"{location}: expected-only key {key!r} belongs in expected.json")
            check_expected_only_keys(child, f"{location}.{key}", errors)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            check_expected_only_keys(child, f"{location}[{index}]", errors)


def check_html(text: str, location: str, errors: list[str]) -> None:
    lower = text.lower()
    normalized = normalize_token(text)
    explicit_markers = ("set-cookie", "authorization:", 'type="password"', "type='password'")
    if any(marker in lower for marker in explicit_markers):
        errors.append(f"{location}: HTML contains sensitive content")
        return
    fragment = next((item for item in FORBIDDEN_KEY_FRAGMENTS if item in normalized), None)
    if fragment:
        errors.append(f"{location}: HTML contains sensitive content ({fragment})")


def canonical_manifest_path(raw_path: Any, owner: str, errors: list[str]) -> str | None:
    if not isinstance(raw_path, str) or not raw_path.strip():
        errors.append(f"{owner}: fixture path must be a non-empty string")
        return None
    if raw_path != raw_path.strip():
        errors.append(f"{owner}: fixture path must not have surrounding whitespace: {raw_path!r}")
        return None
    if "\\" in raw_path:
        errors.append(f"{owner}: fixture path must use forward slashes: {raw_path}")
        return None
    if raw_path.startswith("./") or "//" in raw_path or raw_path.endswith("/"):
        errors.append(f"{owner}: fixture path must be canonical: {raw_path}")
        return None
    windows_path = PureWindowsPath(raw_path)
    if PurePosixPath(raw_path).is_absolute() or windows_path.is_absolute() or windows_path.drive:
        errors.append(f"{owner}: fixture path must stay within fixture root: {raw_path}")
        return None
    path = PurePosixPath(raw_path)
    if any(part in {"", ".", ".."} for part in raw_path.split("/")):
        errors.append(f"{owner}: fixture path must stay within fixture root: {raw_path}")
        return None
    if any(ord(character) < 32 or character == ":" for character in raw_path):
        errors.append(f"{owner}: fixture path contains a non-portable character: {raw_path!r}")
        return None
    return path.as_posix()


def check_json_file(path: Path, is_input: bool, errors: list[str]) -> None:
    document = read_json(path, errors)
    if document is INVALID_JSON:
        return
    if not isinstance(document, (dict, list)):
        errors.append(f"{path}: fixture JSON root must be an object or array")
        return
    check_sensitive_json(document, str(path), errors)
    if is_input:
        check_expected_only_keys(document, str(path), errors)


def collect_fixture_files(root: Path, errors: list[str]) -> set[str]:
    files: set[str] = set()
    try:
        entries = list(root.rglob("*"))
    except OSError as exc:
        errors.append(f"cannot enumerate fixture root {root}: {exc}")
        return files
    for entry in entries:
        relative = entry.relative_to(root).as_posix()
        if entry.is_symlink():
            errors.append(f"fixture tree must not contain symbolic links: {relative}")
            continue
        if not entry.is_file():
            continue
        if "/" not in relative:
            if relative not in ALLOWED_ROOT_FILES:
                errors.append(f"unexpected file at fixture root: {relative}")
            continue
        if entry.suffix.lower() not in ALLOWED_FIXTURE_SUFFIXES:
            errors.append(f"unsupported fixture file type: {relative}")
        files.add(relative)
    return files


def require_exact_keys(
    document: dict[str, Any], allowed: set[str], required: set[str], location: str, errors: list[str]
) -> None:
    missing = sorted(required - document.keys())
    unknown = sorted(document.keys() - allowed)
    if missing:
        errors.append(f"{location}: missing required fields: {', '.join(missing)}")
    if unknown:
        errors.append(f"{location}: unknown fields: {', '.join(unknown)}")


def validate(root: str | Path) -> ValidationResult:
    fixture_root = Path(root).expanduser().resolve()
    errors: list[str] = []
    if not fixture_root.is_dir():
        return ValidationResult(fixture_root, 0, 0, (f"fixture root is not a directory: {fixture_root}",))

    version_match = VERSION_DIRECTORY_PATTERN.fullmatch(fixture_root.name)
    if version_match is None:
        errors.append(
            f"fixture version root directory must be named vN with N >= 1: {fixture_root.name}"
        )
        expected_schema_version = None
    else:
        expected_schema_version = int(version_match.group(1))

    tree_files = collect_fixture_files(fixture_root, errors)
    readme_path = fixture_root / "README.md"
    if not readme_path.is_file():
        errors.append(f"required fixture README does not exist: {readme_path}")
    elif not readme_path.is_symlink():
        read_utf8(readme_path, errors)

    manifest_path = fixture_root / "manifest.json"
    if not manifest_path.is_file():
        errors.append(f"required fixture manifest does not exist: {manifest_path}")
        return ValidationResult(fixture_root, 0, len(tree_files), tuple(errors))
    if manifest_path.is_symlink():
        return ValidationResult(fixture_root, 0, len(tree_files), tuple(errors))
    manifest = read_json(manifest_path, errors)
    if not isinstance(manifest, dict):
        if manifest is not INVALID_JSON:
            errors.append(f"{manifest_path}: manifest JSON root must be an object")
        return ValidationResult(fixture_root, 0, len(tree_files), tuple(errors))

    require_exact_keys(manifest, MANIFEST_FIELDS, MANIFEST_FIELDS, "manifest", errors)
    check_sensitive_json(manifest, "manifest", errors)
    if (
        expected_schema_version is not None
        and (
            type(manifest.get("schemaVersion")) is not int
            or manifest.get("schemaVersion") != expected_schema_version
        )
    ):
        errors.append(f"manifest.schemaVersion must be integer {expected_schema_version}")
    if manifest.get("suite") != EXPECTED_SUITE:
        errors.append(f"manifest.suite must be {EXPECTED_SUITE!r}")
    if manifest.get("businessTimeZone") != EXPECTED_TIME_ZONE:
        errors.append(f"manifest.businessTimeZone must be {EXPECTED_TIME_ZONE!r}")

    scenarios = manifest.get("scenarios")
    if not isinstance(scenarios, list):
        errors.append("manifest.scenarios must be an array")
        scenarios = []
    if expected_schema_version == 1 and len(scenarios) != len(EXPECTED_SCENARIOS):
        errors.append(
            f"manifest.scenarios must contain exactly {len(EXPECTED_SCENARIOS)} scenarios; found {len(scenarios)}"
        )
    elif expected_schema_version is not None and not scenarios:
        errors.append("manifest.scenarios must contain at least one scenario")

    ids: set[str] = set()
    references: dict[str, str] = {}
    input_paths: set[str] = set()
    expected_paths: set[str] = set()
    html_paths: set[str] = set()
    for index, scenario in enumerate(scenarios):
        location = f"manifest.scenarios[{index}]"
        if not isinstance(scenario, dict):
            errors.append(f"{location} must be an object")
            continue
        require_exact_keys(scenario, SCENARIO_FIELDS, {"id", "kind", "input", "expected"}, location, errors)
        scenario_id = scenario.get("id")
        if not isinstance(scenario_id, str) or not scenario_id:
            errors.append(f"{location}.id must be a non-empty string")
            owner = location
        else:
            owner = scenario_id
            if STABLE_KEBAB_CASE_PATTERN.fullmatch(scenario_id) is None:
                errors.append(
                    f"{location}.id must use stable kebab-case: {scenario_id!r}"
                )
            if scenario_id in ids:
                errors.append(f"duplicate scenario id: {scenario_id}")
            ids.add(scenario_id)
        kind = scenario.get("kind")
        if not isinstance(kind, str):
            errors.append(f"{location}.kind is unsupported: {kind!r}")
        elif STABLE_KEBAB_CASE_PATTERN.fullmatch(kind) is None:
            errors.append(
                f"{location}.kind must use stable kebab-case: {kind!r}"
            )
        elif expected_schema_version == 1 and kind not in SUPPORTED_KINDS:
            errors.append(f"{location}.kind is unsupported: {kind!r}")
        elif (
            expected_schema_version == 1
            and isinstance(scenario_id, str)
            and scenario_id in EXPECTED_SCENARIO_KINDS
        ):
            expected_kind = EXPECTED_SCENARIO_KINDS[scenario_id]
            if kind != expected_kind:
                errors.append(f"{location} id {scenario_id!r} must use kind {expected_kind!r}, found {kind!r}")
            required_resources = EXPECTED_SCENARIO_RESOURCE_FIELDS.get(scenario_id, set())
            missing_resources = sorted(required_resources - scenario.keys())
            if missing_resources:
                errors.append(
                    f"{location} id {scenario_id!r} is missing required resources: "
                    + ", ".join(missing_resources)
                )

        for field, suffix, bucket in (
            ("input", ".json", input_paths),
            ("expected", ".json", expected_paths),
            ("html", ".html", html_paths),
        ):
            if field not in scenario:
                continue
            path = canonical_manifest_path(scenario[field], f"{owner}:{field}", errors)
            if path is None:
                continue
            if not path.endswith(suffix):
                errors.append(f"{owner}:{field} must reference a {suffix} file: {path}")
            previous = references.get(path)
            if previous is not None:
                errors.append(f"fixture path referenced more than once: {path} ({previous}, {owner}:{field})")
            else:
                references[path] = f"{owner}:{field}"
            bucket.add(path)
            target = fixture_root.joinpath(*PurePosixPath(path).parts)
            if not target.is_file() or target.is_symlink():
                errors.append(f"referenced fixture file does not exist: {path}")

    if expected_schema_version == 1:
        missing_ids = sorted(EXPECTED_SCENARIOS - ids)
        extra_ids = sorted(ids - EXPECTED_SCENARIOS)
        if missing_ids:
            errors.append(f"missing required scenario ids: {', '.join(missing_ids)}")
        if extra_ids:
            errors.append(f"unexpected scenario ids: {', '.join(extra_ids)}")

    referenced_files = set(references)
    unreferenced = sorted(tree_files - referenced_files)
    missing_from_tree = sorted(referenced_files - tree_files)
    for path in unreferenced:
        errors.append(f"fixture file is not referenced by manifest: {path}")
    for path in missing_from_tree:
        if not any(f"does not exist: {path}" in error for error in errors):
            errors.append(f"manifest references a file outside the fixture tree: {path}")

    for path in sorted(tree_files):
        target = fixture_root.joinpath(*PurePosixPath(path).parts)
        if path.endswith(".json"):
            check_json_file(target, path in input_paths, errors)
        elif path.endswith(".html"):
            text = read_utf8(target, errors)
            if text is not None:
                check_html(text, str(target), errors)

    return ValidationResult(fixture_root, len(scenarios), len(tree_files), tuple(errors))


def validate_corpus(root: str | Path) -> CorpusValidationResult:
    corpus_root = Path(root).expanduser().resolve()
    errors: list[str] = []
    if not corpus_root.is_dir():
        return CorpusValidationResult(
            corpus_root,
            0,
            0,
            0,
            (f"golden fixture corpus root is not a directory: {corpus_root}",),
        )

    version_directories: list[tuple[int, Path]] = []
    try:
        entries = sorted(corpus_root.iterdir(), key=lambda entry: entry.name)
    except OSError as exc:
        return CorpusValidationResult(
            corpus_root, 0, 0, 0, (f"cannot enumerate fixture corpus {corpus_root}: {exc}",)
        )

    for entry in entries:
        match = VERSION_DIRECTORY_PATTERN.fullmatch(entry.name)
        if entry.is_symlink():
            errors.append(f"fixture corpus must not contain symbolic links: {entry.name}")
        elif entry.is_dir() and match is not None:
            version_directories.append((int(match.group(1)), entry))
        elif entry.is_dir():
            errors.append(f"unexpected directory in fixture corpus: {entry.name}")
        else:
            errors.append(f"unexpected file in fixture corpus: {entry.name}")

    version_directories.sort(key=lambda item: item[0])
    versions = [version for version, _ in version_directories]
    if not versions:
        errors.append("fixture corpus must contain at least v1")
    else:
        expected_versions = list(range(1, versions[-1] + 1))
        if versions != expected_versions:
            errors.append(
                "fixture corpus versions must be contiguous from v1; "
                f"found {', '.join(f'v{version}' for version in versions)}"
            )

    scenario_count = 0
    file_count = 0
    for _, version_directory in version_directories:
        result = validate(version_directory)
        scenario_count += result.scenario_count
        file_count += result.file_count
        errors.extend(result.errors)

    return CorpusValidationResult(
        corpus_root,
        len(version_directories),
        scenario_count,
        file_count,
        tuple(errors),
    )


def default_fixture_root() -> Path:
    return Path(__file__).resolve().parents[1] / "contract-fixtures" / "golden"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "fixture_root",
        nargs="?",
        type=Path,
        default=default_fixture_root(),
        help=(
            "golden fixture corpus or one vN root "
            "(default: repository contract-fixtures/golden)"
        ),
    )
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = args.fixture_root.expanduser().resolve()
    if not root.is_dir():
        print(f"error: fixture root is not a directory: {root}", file=sys.stderr)
        return 2
    result = validate(root) if (root / "manifest.json").is_file() else validate_corpus(root)
    if not result.ok:
        print(
            f"Golden fixture validation failed with {len(result.errors)} error(s):",
            file=sys.stderr,
        )
        print(result.format_errors(), file=sys.stderr)
        return 1
    if isinstance(result, CorpusValidationResult):
        print(
            f"Validated {result.version_count} golden fixture version(s), "
            f"{result.scenario_count} scenarios and {result.file_count} referenced "
            f"fixture files in {root}"
        )
    else:
        print(
            f"Validated {result.scenario_count} scenarios and {result.file_count} "
            f"referenced fixture files in {root}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
