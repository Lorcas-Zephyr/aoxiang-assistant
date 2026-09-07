import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts" / "package_ios_ipa.py"


def load_packager():
    spec = importlib.util.spec_from_file_location("package_ios_ipa", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load IPA packager")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PackageIOSIPATest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.packager = load_packager()

    def tearDown(self):
        self.tempdir.cleanup()

    def make_app_bundle(self) -> Path:
        app = self.root / "AoxiangAssistant.app"
        app.mkdir()
        (app / "Info.plist").write_text("fixture plist", encoding="utf-8")
        (app / "AoxiangAssistant").write_bytes(b"fixture executable")
        widget = app / "PlugIns" / "AoxiangAssistantWidget.appex"
        widget.mkdir(parents=True)
        (widget / "Info.plist").write_text("fixture widget plist", encoding="utf-8")
        return app

    def test_packages_app_and_widget_under_standard_payload_directory(self):
        output = self.root / "out" / "AoxiangAssistant-re-signable.ipa"

        self.packager.package_ipa(self.make_app_bundle(), output)

        self.assertTrue(output.is_file())
        with zipfile.ZipFile(output) as archive:
            names = set(archive.namelist())
        self.assertIn("Payload/AoxiangAssistant.app/Info.plist", names)
        self.assertIn("Payload/AoxiangAssistant.app/AoxiangAssistant", names)
        self.assertIn(
            "Payload/AoxiangAssistant.app/PlugIns/AoxiangAssistantWidget.appex/Info.plist",
            names,
        )
        self.assertTrue(all(not name.startswith("/") for name in names))
        self.assertTrue(all(".." not in Path(name).parts for name in names))

    def test_invalid_bundle_does_not_replace_existing_ipa(self):
        broken_bundle = self.root / "Broken.app"
        broken_bundle.mkdir()
        output = self.root / "AoxiangAssistant-re-signable.ipa"
        output.write_bytes(b"known-good-ipa")

        with self.assertRaises(self.packager.IPAPackagingError):
            self.packager.package_ipa(broken_bundle, output)

        self.assertEqual(b"known-good-ipa", output.read_bytes())

    def test_rejects_a_non_app_directory_before_writing(self):
        not_an_app = self.root / "Applications" / "AoxiangAssistant"
        not_an_app.mkdir(parents=True)
        (not_an_app / "Info.plist").write_text("fixture plist", encoding="utf-8")

        with self.assertRaises(self.packager.IPAPackagingError):
            self.packager.package_ipa(not_an_app, self.root / "out.ipa")


if __name__ == "__main__":
    unittest.main()
