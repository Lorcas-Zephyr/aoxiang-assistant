import hashlib
import json
import struct
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "ios" / "AoxiangAssistant" / "Branding" / "AoxiangAssistantIcon.png"
ICON_SET = REPO_ROOT / "ios" / "AoxiangAssistant" / "Assets.xcassets" / "AppIcon.appiconset"
CONTENTS = ICON_SET / "Contents.json"

# This hash records the artwork approved for the current iOS delivery build.
APPROVED_SOURCE_SHA256 = "19940c2923d80ff088b87c8fe54591da640b3649fe2dcc916b4bbe23c1592e87"


def png_header(path: Path) -> tuple[int, int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise AssertionError(f"not a PNG: {path}")
    width, height, _bit_depth, color_type = struct.unpack(">IIBB", data[16:26])
    return width, height, color_type


class IOSAppIconAssetTest(unittest.TestCase):
    def test_approved_source_is_present_and_stable(self):
        self.assertTrue(SOURCE.is_file())
        digest = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
        self.assertEqual(APPROVED_SOURCE_SHA256, digest)
        self.assertEqual(("R", "G", "B"), png_channels(SOURCE))

    def test_every_declared_slot_has_exact_dimensions_and_opaque_rgb_pixels(self):
        contents = json.loads(CONTENTS.read_text(encoding="utf-8"))
        self.assertEqual(1, contents["info"]["version"])
        declared = contents["images"]
        self.assertEqual(18, len(declared))
        for image in declared:
            filename = image["filename"]
            icon = ICON_SET / filename
            self.assertTrue(icon.is_file(), filename)
            logical_width, logical_height = image["size"].split("x")
            scale = int(image["scale"].removesuffix("x"))
            expected_width = round(float(logical_width) * scale)
            expected_height = round(float(logical_height) * scale)
            width, height, color_type = png_header(icon)
            self.assertEqual((expected_width, expected_height), (width, height), filename)
            self.assertEqual(2, color_type, f"{filename} must be opaque RGB")


def png_channels(path: Path) -> tuple[str, ...]:
    color_type = png_header(path)[2]
    return {0: ("L",), 2: ("R", "G", "B"), 3: ("P",), 4: ("LA",), 6: ("R", "G", "B", "A")}[color_type]


if __name__ == "__main__":
    unittest.main()
