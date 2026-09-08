import re
import unittest
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PROJECT_FILE = REPO_ROOT / "ios" / "AoxiangAssistant.xcodeproj" / "project.pbxproj"
APP_ICON_SET = (
    REPO_ROOT
    / "ios"
    / "AoxiangAssistant"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
)
ICON_SOURCE_FILE = (
    REPO_ROOT
    / "ios"
    / "AoxiangAssistant"
    / "Branding"
    / "AoxiangAssistantIcon.png"
)
IOS_ENTRYPOINT_FILE = REPO_ROOT / "ios" / "AoxiangAssistant" / "App" / "AoxiangAssistantEntryPoint.swift"
IOS_OFFLINE_VIEWS_FILE = REPO_ROOT / "ios" / "AoxiangApp" / "Sources" / "AoxiangApp" / "OfflineViews.swift"
IOS_AUTHENTICATION_VIEW_FILE = REPO_ROOT / "ios" / "AoxiangApp" / "Sources" / "AoxiangApp" / "VisibleAuthenticationWebView.swift"
IOS_SHARED_CONTAINER_FILE = REPO_ROOT / "ios" / "AoxiangCore" / "Sources" / "AoxiangCore" / "SharedContainer.swift"
IOS_WIDGET_FILE = REPO_ROOT / "ios" / "AoxiangAssistant" / "Widget" / "AoxiangWidget.swift"
IOS_APP_ENTITLEMENTS_FILE = REPO_ROOT / "ios" / "AoxiangAssistant" / "App" / "AoxiangAssistant.entitlements"
IOS_WIDGET_ENTITLEMENTS_FILE = REPO_ROOT / "ios" / "AoxiangAssistant" / "Widget" / "AoxiangAssistantWidget.entitlements"
IOS_APP_INFO_FILE = REPO_ROOT / "ios" / "AoxiangAssistant" / "App" / "Info.plist"
IOS_WIDGET_INFO_FILE = REPO_ROOT / "ios" / "AoxiangAssistant" / "Widget" / "Info.plist"
SCHEME_FILE = (
    REPO_ROOT
    / "ios"
    / "AoxiangAssistant.xcodeproj"
    / "xcshareddata"
    / "xcschemes"
    / "AoxiangAssistant.xcscheme"
)
WORKFLOW_FILE = REPO_ROOT / ".github" / "workflows" / "cross-platform-contract.yml"
IPA_WORKFLOW_FILE = REPO_ROOT / ".github" / "workflows" / "ios-re-signable-ipa.yml"
IPA_BUILD_SCRIPT = REPO_ROOT / "scripts" / "build_ios_re_signable_ipa.sh"
SIGNED_IPA_VERIFY_SCRIPT = REPO_ROOT / "scripts" / "verify_signed_ios_ipa.sh"


class IOSProjectConfigurationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.project = PROJECT_FILE.read_text(encoding="utf-8")
        cls.ios_entrypoint = IOS_ENTRYPOINT_FILE.read_text(encoding="utf-8")
        cls.ios_offline_views = IOS_OFFLINE_VIEWS_FILE.read_text(encoding="utf-8")
        cls.ios_authentication_view = IOS_AUTHENTICATION_VIEW_FILE.read_text(encoding="utf-8")
        cls.ios_shared_container = IOS_SHARED_CONTAINER_FILE.read_text(encoding="utf-8")
        cls.ios_widget = IOS_WIDGET_FILE.read_text(encoding="utf-8")
        cls.ios_app_entitlements = IOS_APP_ENTITLEMENTS_FILE.read_text(encoding="utf-8")
        cls.ios_widget_entitlements = IOS_WIDGET_ENTITLEMENTS_FILE.read_text(encoding="utf-8")
        cls.ios_app_info = IOS_APP_INFO_FILE.read_text(encoding="utf-8")
        cls.ios_widget_info = IOS_WIDGET_INFO_FILE.read_text(encoding="utf-8")
        cls.scheme = SCHEME_FILE.read_text(encoding="utf-8")
        cls.workflow = WORKFLOW_FILE.read_text(encoding="utf-8")


    def test_shared_scheme_builds_app_and_widget_targets(self):
        self.assertIn('BlueprintName = "AoxiangAssistant"', self.scheme)
        self.assertIn('BlueprintName = "AoxiangAssistantWidget"', self.scheme)
        identifiers = set(re.findall(r'BlueprintIdentifier = "(A0010001000000000000005[12])"', self.scheme))
        self.assertEqual(
            {"A00100010000000000000051", "A00100010000000000000052"},
            identifiers,
        )

    def test_widget_source_is_in_widget_target(self):
        self.assertIn(
            "AoxiangWidget.swift in Sources",
            self.project,
            "the Widget implementation must be compiled by the extension target",
        )
        self.assertIn(
            "A00100010000000000000017 /* AoxiangWidget.swift */",
            self.project,
        )

    def test_widget_depends_on_core_but_never_on_full_app(self):
        target = self._target_block("A00100010000000000000052")
        self.assertIn("A00100010000000000000124 /* AoxiangCore */", target)
        self.assertNotIn("AoxiangApp", target)

    def test_app_has_app_and_explicit_core_products(self):
        target = self._target_block("A00100010000000000000051")
        self.assertIn("AoxiangApp", target)
        self.assertIn("AoxiangCore", target)

    def test_package_products_are_linked_into_their_target_frameworks(self):
        self.assertEqual(
            {"AoxiangApp", "AoxiangCore"},
            set(self._framework_product_names_for_target("A00100010000000000000051")),
        )
        self.assertEqual(
            ["AoxiangCore"],
            self._framework_product_names_for_target("A00100010000000000000052"),
        )

    def test_ios_app_has_one_formal_lifecycle_entrypoint(self):
        """The shipping iPhone/iPad app must have one @main and one scheduler owner."""
        self.assertEqual(self.ios_entrypoint.count("@main"), 1)
        self.assertIn("struct AoxiangAssistantEntryPoint: App", self.ios_entrypoint)
        self.assertIn("IOSApplicationLifecycle", self.ios_entrypoint)
        self.assertNotIn("AoxiangApplication", self.ios_entrypoint)
        source_files = self._source_files_for_target("A00100010000000000000051")
        self.assertEqual(source_files, ["AoxiangAssistantEntryPoint.swift"])

    def test_app_and_widget_are_ios_only_and_support_iphone_ipad(self):
        for target_id in ("A00100010000000000000051", "A00100010000000000000052"):
            target = self._build_configuration_block(target_id)
            self.assertIn('SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";', target)
            self.assertIn('TARGETED_DEVICE_FAMILY = "1,2";', target)
            self.assertIn("SUPPORTS_MACCATALYST = NO;", target)

    def test_ios_appicon_uses_the_approved_project_artwork(self):
        contents_file = APP_ICON_SET / "Contents.json"
        self.assertTrue(contents_file.is_file(), "iOS AppIcon asset catalog is required")
        contents = json.loads(contents_file.read_text(encoding="utf-8"))
        self.assertEqual({"images", "info"}, set(contents))
        self.assertEqual(1, contents["info"]["version"])
        self.assertEqual("xcode", contents["info"]["author"])
        images = contents["images"]
        self.assertTrue(
            any(image.get("idiom") == "ios-marketing" and image.get("size") == "1024x1024" for image in images),
            "App Store marketing icon must be declared",
        )
        self.assertTrue(
            any(image.get("idiom") == "ipad" and image.get("size") == "83.5x83.5" for image in images),
            "iPad Pro icon slot must be declared",
        )
        for image in images:
            filename = image.get("filename")
            if filename:
                icon_file = APP_ICON_SET / filename
                self.assertTrue(icon_file.is_file(), f"missing AppIcon image: {filename}")
                self.assertEqual("png", icon_file.suffix.lower().lstrip("."))

        self.assertTrue(ICON_SOURCE_FILE.is_file(), "approved icon source is required")
        self.assertGreater(ICON_SOURCE_FILE.stat().st_size, 1000)
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", self.project)
        self.assertIn("Assets.xcassets in Resources", self.project)
        app_group = self._object_in_section("PBXGroup", "A00100010000000000000082")
        self.assertIn("Assets.xcassets", app_group)
        app_group = self._object_in_section("PBXGroup", "A00100010000000000000084")
        self.assertNotIn("Assets.xcassets", app_group)

    def test_swiftui_surfaces_are_ios_only(self):
        self.assertIn("#if os(iOS) && canImport(SwiftUI)", self.ios_offline_views)
        self.assertIn(
            "#if os(iOS) && canImport(SwiftUI) && canImport(WebKit)",
            self.ios_authentication_view,
        )
        self.assertNotIn("NSViewRepresentable", self.ios_authentication_view)

    def test_widget_snapshot_requires_the_app_group_on_ios(self):
        self.assertIn("public static func sharedSnapshotURL", self.ios_shared_container)
        self.assertIn("#if os(iOS)", self.ios_shared_container)
        self.assertIn("return nil", self.ios_shared_container)
        self.assertIn("sharedSnapshotURL", self.ios_widget)
        self.assertNotIn("snapshotURL()", self.ios_widget)

    def test_signed_targets_can_use_the_signers_registered_identifiers(self):
        self.assertIn("AOXIANG_APP_BUNDLE_IDENTIFIER", self.project)
        self.assertIn("AOXIANG_WIDGET_BUNDLE_IDENTIFIER", self.project)
        self.assertIn("AOXIANG_APP_GROUP_IDENTIFIER", self.project)
        self.assertIn("$(AOXIANG_APP_GROUP_IDENTIFIER)", self.ios_app_entitlements)
        self.assertIn("$(AOXIANG_APP_GROUP_IDENTIFIER)", self.ios_widget_entitlements)
        self.assertIn("AoxiangAppGroupIdentifier", self.ios_app_info)
        self.assertIn("AoxiangAppGroupIdentifier", self.ios_widget_info)

    def test_manual_ipa_workflow_exposes_non_secret_signing_identity_inputs(self):
        workflow = IPA_WORKFLOW_FILE.read_text(encoding="utf-8")
        for input_name in (
            "app_bundle_identifier",
            "widget_bundle_identifier",
            "app_group_identifier",
        ):
            self.assertIn(f"{input_name}:", workflow)
            self.assertIn(f"inputs.{input_name}", workflow)

    def test_macos_ci_builds_shared_ios_scheme_without_signing(self):
        self.assertIn("runs-on: macos-latest", self.workflow)
        self.assertIn("xcodebuild", self.workflow)
        self.assertIn("-project AoxiangAssistant.xcodeproj", self.workflow)
        self.assertIn("-scheme AoxiangAssistant", self.workflow)
        self.assertIn("-sdk iphonesimulator", self.workflow)
        self.assertIn("-destination 'generic/platform=iOS Simulator'", self.workflow)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", self.workflow)
        self.assertIn("CODE_SIGNING_REQUIRED=NO", self.workflow)
        self.assertIn("AoxiangAssistantWidget.appex", self.workflow)

    def test_manual_macos_workflow_creates_a_re_signable_device_ipa(self):
        workflow = IPA_WORKFLOW_FILE.read_text(encoding="utf-8")

        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("runs-on: macos-latest", workflow)
        self.assertIn("bash scripts/build_ios_re_signable_ipa.sh", workflow)
        self.assertIn("actions/upload-artifact@", workflow)
        self.assertIn("AoxiangAssistant-sideload-re-signable.ipa", workflow)
        self.assertIn("AoxiangAssistant-full-widget-re-signable.ipa", workflow)
        self.assertIn("ios-artifacts", workflow)
        self.assertNotIn("security import", workflow)
        self.assertNotIn("APPLE_CERTIFICATE", workflow)

    def test_re_signable_ipa_builder_archives_iphoneos_without_signing_secrets(self):
        script = IPA_BUILD_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("-sdk iphoneos", script)
        self.assertIn("generic/platform=iOS", script)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", script)
        self.assertIn("CODE_SIGNING_REQUIRED=NO", script)
        self.assertIn("package_ios_ipa.py", script)
        self.assertIn("AoxiangAssistantWidget.appex", script)
        self.assertIn("--variant sideload", script)
        self.assertIn("--variant full", script)
        self.assertNotIn("security import", script)
        self.assertNotIn("provisioning profile", script.lower())

    def test_re_signable_ipa_builder_passes_team_owned_identifiers_to_xcodebuild(self):
        script = IPA_BUILD_SCRIPT.read_text(encoding="utf-8")
        for setting in (
            "AOXIANG_APP_BUNDLE_IDENTIFIER",
            "AOXIANG_WIDGET_BUNDLE_IDENTIFIER",
            "AOXIANG_APP_GROUP_IDENTIFIER",
        ):
            self.assertIn(setting, script)

    def test_signed_ipa_verifier_checks_nested_code_and_shared_entitlements(self):
        script = SIGNED_IPA_VERIFY_SCRIPT.read_text(encoding="utf-8")
        for required in (
            "codesign --verify --deep --strict",
            "AoxiangAssistantWidget.appex",
            "embedded.mobileprovision",
            "application-groups",
            "security cms",
        ):
            self.assertIn(required, script)

    def _target_block(self, target_id):
        return self._object_in_section("PBXNativeTarget", target_id)

    def _source_files_for_target(self, target_id):
        """Resolve the target's PBXSourcesBuildPhase instead of scanning the target block."""
        target = self._target_block(target_id)
        phase_ids = re.findall(
            r"A[0-9A-F]+ /\* Sources \*/",
            target,
        )
        self.assertEqual(1, len(phase_ids), "target must have one Sources build phase")
        phase_id = phase_ids[0].split(" /", 1)[0]
        phase = self._object_in_section("PBXSourcesBuildPhase", phase_id)
        return re.findall(r"/\* ([^*]+) in Sources \*/", phase)

    def _framework_product_names_for_target(self, target_id):
        target = self._target_block(target_id)
        phase_ids = re.findall(
            r"(A[0-9A-F]+) /\* Frameworks \*/",
            target,
        )
        self.assertEqual(1, len(phase_ids), "target must have one Frameworks build phase")
        phase = self._object_in_section("PBXFrameworksBuildPhase", phase_ids[0])
        build_file_ids = re.findall(r"\b(A[0-9A-F]+) /\* .*? in Frameworks \*/", phase)
        names = []
        for build_file_id in build_file_ids:
            build_file = self._object_in_section("PBXBuildFile", build_file_id)
            product = re.search(r"productRef = A[0-9A-F]+ /\* ([^*]+) \*/", build_file)
            self.assertIsNotNone(product, "framework product must be linked by productRef")
            names.append(product.group(1))
        return names

    def _build_configuration_block(self, target_id):
        target = self._target_block(target_id)
        config_ids = re.findall(r"buildConfigurationList = (A\d+) /\* Build configuration list", target)
        self.assertEqual(1, len(config_ids))
        config_list = self._object_in_section("XCConfigurationList", config_ids[0])
        config_ids = re.findall(
            r"A\d+ /\* (?:Debug|Release) \*/",
            config_list,
        )
        self.assertEqual(2, len(config_ids))
        return "\n".join(
            self._configuration_block(config_id.split(" /", 1)[0])
            for config_id in config_ids
        )

    def _configuration_block(self, config_id):
        return self._object_in_section("XCBuildConfiguration", config_id)

    def _object_in_section(self, section_name, object_id):
        start_marker = f"/* Begin {section_name} section */"
        end_marker = f"/* End {section_name} section */"
        start = self.project.find(start_marker)
        end = self.project.find(end_marker, start)
        self.assertGreaterEqual(start, 0, f"{section_name} section must exist")
        self.assertGreater(end, start, f"{section_name} section must be closed")
        section = self.project[start:end]
        object_match = re.search(
            rf"(?m)^\s*{re.escape(object_id)} /\*.*?\*/ = ",
            section,
        )
        self.assertIsNotNone(object_match, f"{object_id} must exist in {section_name}")
        next_object = re.search(r"(?m)^\t\tA[0-9A-F]+ /\*", section[object_match.end():])
        object_end = object_match.end() + (next_object.start() if next_object else len(section))
        return section[object_match.start():object_end]


if __name__ == "__main__":
    unittest.main()
