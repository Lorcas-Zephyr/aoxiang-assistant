#!/usr/bin/env python3
"""Package a validated, unsigned iOS app bundle for later device re-signing.

This helper deliberately does not sign code or accept any certificate,
provisioning profile, password, or Apple account material. It turns an app
bundle produced by a macOS `xcodebuild archive` into the standard
`Payload/<App>.app` IPA layout. A re-signer must apply a valid device signing
identity afterwards.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


class IPAPackagingError(ValueError):
    """The archive bundle cannot be safely packaged as a re-signable IPA."""


def package_ipa(app_path: Path | str, output_path: Path | str) -> Path:
    """Atomically package the Aoxiang app and Widget bundle into an IPA.

    The result is intentionally unsigned. Existing output is left untouched
    until the complete ZIP has been written and closed successfully.
    """

    app = Path(app_path)
    output = Path(output_path)
    _validate_bundle(app, output)

    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.", suffix=".tmp", dir=output.parent
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        with zipfile.ZipFile(
            temporary,
            mode="w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=9,
            strict_timestamps=False,
        ) as archive:
            for item in sorted(app.rglob("*"), key=lambda path: path.as_posix()):
                if item.is_dir():
                    continue
                if item.is_symlink():
                    raise IPAPackagingError(
                        f"refusing symlink in app bundle: {item.relative_to(app)}"
                    )
                if not item.is_file():
                    raise IPAPackagingError(
                        f"refusing non-file bundle entry: {item.relative_to(app)}"
                    )
                relative = item.relative_to(app)
                archive_name = PurePosixPath("Payload") / app.name / relative.as_posix()
                archive.write(item, arcname=str(archive_name))
        os.replace(temporary, output)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    return output


def _validate_bundle(app: Path, output: Path) -> None:
    if app.suffix != ".app":
        raise IPAPackagingError("app bundle must use the .app suffix")
    if not app.is_dir():
        raise IPAPackagingError(f"app bundle is not a directory: {app}")
    if not (app / "Info.plist").is_file():
        raise IPAPackagingError("app bundle is missing Info.plist")

    widget_info = app / "PlugIns" / "AoxiangAssistantWidget.appex" / "Info.plist"
    if not widget_info.is_file():
        raise IPAPackagingError("app bundle is missing the Aoxiang Widget extension")

    try:
        output.resolve().relative_to(app.resolve())
    except ValueError:
        return
    raise IPAPackagingError("output IPA must not be placed inside the app bundle")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Package an unsigned iOS App + Widget bundle for later re-signing."
    )
    parser.add_argument("--app-path", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    try:
        output = package_ipa(arguments.app_path, arguments.output)
    except IPAPackagingError as error:
        parser.error(str(error))
    print(f"Created unsigned, re-signable IPA: {output}")
    print(f"SHA256: {_sha256(output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
