#!/usr/bin/env bash
set -euo pipefail

# Builds an unsigned device archive on macOS and packages it for later
# re-signing. It never accepts or imports certificates, signing assets, Apple
# IDs, passwords, or App Store credentials.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${IOS_CONFIGURATION:-Release}"
output_ipa="${IOS_RE_SIGNABLE_IPA_OUTPUT:-$repo_root/dist/ios/AoxiangAssistant-re-signable.ipa}"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/aoxiang-device-archive.XXXXXX")"
archive_path="$temporary_root/AoxiangAssistant.xcarchive"

cleanup() {
  rm -rf "$temporary_root"
}
trap cleanup EXIT

xcodebuild \
  -project "$repo_root/ios/AoxiangAssistant.xcodeproj" \
  -scheme AoxiangAssistant \
  -configuration "$configuration" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$temporary_root/DerivedData" \
  -archivePath "$archive_path" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  archive

app_path="$archive_path/Products/Applications/AoxiangAssistant.app"
widget_path="$app_path/PlugIns/AoxiangAssistantWidget.appex"
test -f "$app_path/Info.plist"
test -f "$widget_path/Info.plist"

python3 "$repo_root/scripts/package_ios_ipa.py" \
  --app-path "$app_path" \
  --output "$output_ipa"
