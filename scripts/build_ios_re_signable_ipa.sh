#!/usr/bin/env bash
set -euo pipefail

# Builds an unsigned device archive on macOS and packages it for later
# re-signing. It never accepts or imports certificates, signing assets, Apple
# IDs, passwords, or App Store credentials.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${IOS_CONFIGURATION:-Release}"
output_dir="${IOS_RE_SIGNABLE_IPA_OUTPUT_DIR:-$repo_root/dist/ios}"
app_bundle_identifier="${IOS_APP_BUNDLE_IDENTIFIER:-cn.nwpu.aoxiangassistant}"
widget_bundle_identifier="${IOS_WIDGET_BUNDLE_IDENTIFIER:-cn.nwpu.aoxiangassistant.widget}"
app_group_identifier="${IOS_APP_GROUP_IDENTIFIER:-group.cn.nwpu.aoxiang-assistant}"
expected_marketing_version="${IOS_EXPECTED_MARKETING_VERSION:-1.0.1}"
expected_build_version="${IOS_EXPECTED_BUILD_VERSION:-2}"

if [[ ! "$app_bundle_identifier" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "invalid host bundle identifier: $app_bundle_identifier" >&2
  exit 2
fi
if [[ ! "$widget_bundle_identifier" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "invalid Widget bundle identifier: $widget_bundle_identifier" >&2
  exit 2
fi
if [[ "$widget_bundle_identifier" != "${app_bundle_identifier}."* ]]; then
  echo "Widget bundle identifier must extend the host bundle identifier: $widget_bundle_identifier" >&2
  exit 2
fi
if [[ ! "$app_group_identifier" =~ ^group\.[A-Za-z0-9.-]+$ ]]; then
  echo "invalid App Group identifier: $app_group_identifier" >&2
  exit 2
fi
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
  AOXIANG_APP_BUNDLE_IDENTIFIER="$app_bundle_identifier" \
  AOXIANG_WIDGET_BUNDLE_IDENTIFIER="$widget_bundle_identifier" \
  AOXIANG_APP_GROUP_IDENTIFIER="$app_group_identifier" \
  archive

app_path="$archive_path/Products/Applications/AoxiangAssistant.app"
widget_path="$app_path/PlugIns/AoxiangAssistantWidget.appex"
test -f "$app_path/Info.plist"
test -f "$widget_path/Info.plist"

plist_value() {
  local plist="$1"
  local key_path="$2"
  /usr/bin/plutil -extract "$key_path" raw -o - "$plist"
}

actual_app_id="$(plist_value "$app_path/Info.plist" CFBundleIdentifier)"
actual_widget_id="$(plist_value "$widget_path/Info.plist" CFBundleIdentifier)"
actual_app_group="$(plist_value "$app_path/Info.plist" AoxiangAppGroupIdentifier)"
actual_widget_group="$(plist_value "$widget_path/Info.plist" AoxiangAppGroupIdentifier)"
actual_marketing_version="$(plist_value "$app_path/Info.plist" CFBundleShortVersionString)"
actual_build_version="$(plist_value "$app_path/Info.plist" CFBundleVersion)"

[[ "$actual_app_id" == "$app_bundle_identifier" ]] || {
  echo "archive host bundle ID mismatch: $actual_app_id (expected $app_bundle_identifier)" >&2
  exit 1
}
[[ "$actual_widget_id" == "$widget_bundle_identifier" ]] || {
  echo "archive Widget bundle ID mismatch: $actual_widget_id (expected $widget_bundle_identifier)" >&2
  exit 1
}
[[ "$actual_widget_id" == "${app_bundle_identifier}."* ]] || {
  echo "archive Widget bundle ID must extend the host bundle ID: $actual_widget_id" >&2
  exit 1
}
[[ "$actual_app_group" == "$app_group_identifier" ]] || {
  echo "archive host App Group mismatch: $actual_app_group (expected $app_group_identifier)" >&2
  exit 1
}
[[ "$actual_widget_group" == "$app_group_identifier" ]] || {
  echo "archive Widget App Group mismatch: $actual_widget_group (expected $app_group_identifier)" >&2
  exit 1
}
[[ "$actual_marketing_version" == "$expected_marketing_version" ]] || {
  echo "archive marketing version mismatch: $actual_marketing_version (expected $expected_marketing_version)" >&2
  exit 1
}
[[ "$actual_build_version" == "$expected_build_version" ]] || {
  echo "archive build version mismatch: $actual_build_version (expected $expected_build_version)" >&2
  exit 1
}
extension_point="$(plist_value "$widget_path/Info.plist" NSExtension.NSExtensionPointIdentifier)"
[[ "$extension_point" == "com.apple.widgetkit-extension" ]] || {
  echo "archive Widget extension point mismatch: $extension_point" >&2
  exit 1
}
if /usr/bin/plutil -extract NSExtension.NSExtensionPrincipalClass raw -o - "$widget_path/Info.plist" >/dev/null 2>&1; then
  echo "archive Widget plist must not declare NSExtensionPrincipalClass" >&2
  exit 1
fi

python3 "$repo_root/scripts/package_ios_ipa.py" \
  --app-path "$app_path" \
  --variant sideload \
  --output "$output_dir/AoxiangAssistant-sideload-re-signable.ipa"

python3 "$repo_root/scripts/package_ios_ipa.py" \
  --app-path "$app_path" \
  --variant sideload-host-only \
  --output "$output_dir/AoxiangAssistant-sideload-host-only-re-signable.ipa"

python3 "$repo_root/scripts/package_ios_ipa.py" \
  --app-path "$app_path" \
  --variant full \
  --output "$output_dir/AoxiangAssistant-full-widget-re-signable.ipa"
