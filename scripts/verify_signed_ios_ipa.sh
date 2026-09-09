#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 4 ]]; then
  echo "usage: $0 SIGNED.ipa [APP_BUNDLE_ID] [WIDGET_BUNDLE_ID] [APP_GROUP_ID]" >&2
  exit 2
fi

ipa_path="$1"
expected_app_id="${2:-cn.nwpu.aoxiangassistant}"
expected_widget_id="${3:-cn.nwpu.aoxiangassistant.widget}"
expected_group="${4:-group.cn.nwpu.aoxiang-assistant}"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/aoxiang-signed-ipa.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT

[[ -f "$ipa_path" ]] || { echo "IPA does not exist: $ipa_path" >&2; exit 1; }
unzip -q "$ipa_path" -d "$temporary_root/payload"

app_path="$temporary_root/payload/Payload/AoxiangAssistant.app"
widget_path="$app_path/PlugIns/AoxiangAssistantWidget.appex"
app_info="$app_path/Info.plist"
widget_info="$widget_path/Info.plist"

for path in "$app_info" "$widget_info" "$app_path/AoxiangAssistant" "$widget_path/AoxiangAssistantWidget"; do
  [[ -e "$path" ]] || { echo "missing signed bundle entry: $path" >&2; exit 1; }
done

[[ -f "$app_path/embedded.mobileprovision" ]] || {
  echo "host bundle is missing embedded.mobileprovision" >&2
  exit 1
}
[[ -f "$widget_path/embedded.mobileprovision" ]] || {
  echo "Widget bundle is missing embedded.mobileprovision" >&2
  exit 1
}

codesign --verify --deep --strict "$widget_path"
codesign --verify --deep --strict "$app_path"

actual_app_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app_info")"
actual_widget_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$widget_info")"
[[ "$actual_app_id" == "$expected_app_id" ]] || {
  echo "host bundle ID mismatch: $actual_app_id (expected $expected_app_id)" >&2
  exit 1
}
[[ "$actual_widget_id" == "$expected_widget_id" ]] || {
  echo "Widget bundle ID mismatch: $actual_widget_id (expected $expected_widget_id)" >&2
  exit 1
}
actual_app_group="$(/usr/bin/plutil -extract AoxiangAppGroupIdentifier raw -o - "$app_info" 2>/dev/null || true)"
actual_widget_group="$(/usr/bin/plutil -extract AoxiangAppGroupIdentifier raw -o - "$widget_info" 2>/dev/null || true)"
[[ "$actual_app_group" == "$expected_group" ]] || {
  echo "host App Group plist mismatch: $actual_app_group (expected $expected_group)" >&2
  exit 1
}
[[ "$actual_widget_group" == "$expected_group" ]] || {
  echo "Widget App Group plist mismatch: $actual_widget_group (expected $expected_group)" >&2
  exit 1
}
extension_point="$(/usr/bin/plutil -extract NSExtension.NSExtensionPointIdentifier raw -o - "$widget_info")"
[[ "$extension_point" == "com.apple.widgetkit-extension" ]] || {
  echo "unexpected extension point: $extension_point" >&2
  exit 1
}

decode_entitlements() {
  local bundle="$1"
  local output="$2"
  codesign -d --entitlements :- "$bundle" > "$output" 2>/dev/null
  grep -Fq "application-groups" "$output" || {
    echo "missing application-groups entitlement: $bundle" >&2
    exit 1
  }
  grep -Fq "<string>$expected_group</string>" "$output" || {
    echo "App Group mismatch in signed entitlements: $bundle" >&2
    exit 1
  }
}

decode_profile() {
  local bundle="$1"
  local output="$2"
  /usr/bin/security cms -D -i "$bundle/embedded.mobileprovision" > "$output"
  grep -Fq "<string>$expected_group</string>" "$output" || {
    echo "App Group missing from provisioning profile: $bundle" >&2
    exit 1
  }
}

decode_entitlements "$widget_path" "$temporary_root/widget-entitlements.plist"
decode_entitlements "$app_path" "$temporary_root/app-entitlements.plist"
decode_profile "$widget_path" "$temporary_root/widget-profile.plist"
decode_profile "$app_path" "$temporary_root/app-profile.plist"

grep -Fq "$expected_app_id" "$temporary_root/app-profile.plist" || {
  echo "host bundle ID is not authorized by its provisioning profile" >&2
  exit 1
}
grep -Fq "$expected_widget_id" "$temporary_root/widget-profile.plist" || {
  echo "Widget bundle ID is not authorized by its provisioning profile" >&2
  exit 1
}

echo "Signed iOS IPA verified: host, nested Widget, profiles and App Group are consistent."
