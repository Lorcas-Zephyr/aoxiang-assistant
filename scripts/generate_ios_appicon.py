#!/usr/bin/env python3
"""Generate iPhone/iPad AppIcon PNGs from the approved project artwork.

The checked-in source PNG is deliberately kept separate from generated
AppIcon slots.  This makes a future artwork replacement reviewable and keeps
the pixel sizes required by Xcode deterministic.  The approved source is
already opaque, and generation rejects an image with an alpha channel.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


SLOTS = (
    ("AppIcon-iphone-20@2x.png", 40, "iphone", "20x20", "2"),
    ("AppIcon-iphone-20@3x.png", 60, "iphone", "20x20", "3"),
    ("AppIcon-iphone-29@2x.png", 58, "iphone", "29x29", "2"),
    ("AppIcon-iphone-29@3x.png", 87, "iphone", "29x29", "3"),
    ("AppIcon-iphone-40@2x.png", 80, "iphone", "40x40", "2"),
    ("AppIcon-iphone-40@3x.png", 120, "iphone", "40x40", "3"),
    ("AppIcon-iphone-60@2x.png", 120, "iphone", "60x60", "2"),
    ("AppIcon-iphone-60@3x.png", 180, "iphone", "60x60", "3"),
    ("AppIcon-ipad-20.png", 20, "ipad", "20x20", "1"),
    ("AppIcon-ipad-20@2x.png", 40, "ipad", "20x20", "2"),
    ("AppIcon-ipad-29.png", 29, "ipad", "29x29", "1"),
    ("AppIcon-ipad-29@2x.png", 58, "ipad", "29x29", "2"),
    ("AppIcon-ipad-40.png", 40, "ipad", "40x40", "1"),
    ("AppIcon-ipad-40@2x.png", 80, "ipad", "40x40", "2"),
    ("AppIcon-ipad-76.png", 76, "ipad", "76x76", "1"),
    ("AppIcon-ipad-76@2x.png", 152, "ipad", "76x76", "2"),
    ("AppIcon-ipad-83.5@2x.png", 167, "ipad", "83.5x83.5", "2"),
    ("AppIcon-1024.png", 1024, "ios-marketing", "1024x1024", "1"),
)


def render_icon(source: Image.Image, size: int) -> Image.Image:
    """Return an opaque, square icon at the exact requested pixel size."""
    return source.resize((size, size), Image.Resampling.LANCZOS).convert("RGB")


def generate(source: Path, output: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(f"icon source does not exist: {source}")
    with Image.open(source) as loaded:
        if loaded.width != loaded.height:
            raise ValueError("icon source must be square")
        if "A" in loaded.getbands():
            raise ValueError("icon source must not contain an alpha channel")
        source_image = loaded.convert("RGB")
    output.mkdir(parents=True, exist_ok=True)
    for filename, size, *_ in SLOTS:
        render_icon(source_image, size).save(output / filename, format="PNG", optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    generate(arguments.source, arguments.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
