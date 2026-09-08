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

if [[ ! "$app_bundle_identifier" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "invalid host bundle identifier: $app_bundle_identifier" >&2
  exit 2
fi
if [[ ! "$widget_bundle_identifier" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "invalid Widget bundle identifier: $widget_bundle_identifier" >&2
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

python3 "$repo_root/scripts/package_ios_ipa.py" \
  --app-path "$app_path" \
  --variant sideload \
  --output "$output_dir/AoxiangAssistant-sideload-re-signable.ipa"

python3 "$repo_root/scripts/package_ios_ipa.py" \
  --app-path "$app_path" \
  --variant full \
  --output "$output_dir/AoxiangAssistant-full-widget-re-signable.ipa"
