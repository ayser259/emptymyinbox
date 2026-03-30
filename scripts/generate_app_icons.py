#!/usr/bin/env python3
"""
Generate Empty My Inbox AppIcon PNGs + Logo from a single vector-style design.
Requires: pip install pillow
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

# Match SharedAppTheme
BG = (10, 10, 10)
ACCENT = (246, 172, 10)


def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    r = int(size * 0.215)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=BG)

    # Safe area ~12% (Apple HIG); envelope fills inner square
    m = int(size * 0.18)
    iw = size - 2 * m
    ix0, iy0 = m, m
    ix1, iy1 = ix0 + iw, iy0 + iw

    # Envelope: trapezoid flap + body (single filled polygon outline + inner cutout optional)
    gold = ACCENT + (255,)
    # Body (lower part)
    body_top = iy0 + int(iw * 0.38)
    draw.rounded_rectangle(
        [ix0, body_top, ix1, iy1],
        radius=max(2, int(size * 0.02)),
        fill=gold,
    )
    # Flap (upper triangle / chevron)
    mid_x = size // 2
    flap_h = int(iw * 0.42)
    flap_pts = [
        (ix0, body_top),
        (mid_x, iy0 + int(iw * 0.08)),
        (ix1, body_top),
    ]
    draw.polygon(flap_pts, fill=gold)
    # Subtle "V" fold line (darker gold)
    fold = (200, 140, 5, 255)
    line_w = max(1, size // 128)
    draw.line(
        [(ix0, body_top), (mid_x, iy0 + int(iw * 0.22)), (ix1, body_top)],
        fill=fold,
        width=line_w,
    )
    return img


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    sizes: list[tuple[str, int]] = [
        ("AppIcon-16.png", 16),
        ("AppIcon-16@2x.png", 32),
        ("AppIcon-32.png", 32),
        ("AppIcon-32@2x.png", 64),
        ("AppIcon-128.png", 128),
        ("AppIcon-128@2x.png", 256),
        ("AppIcon-256.png", 256),
        ("AppIcon-256@2x.png", 512),
        ("AppIcon-512.png", 512),
        ("AppIcon-512@2x.png", 1024),
    ]

    mac_targets = [
        root / "Mac/emptymyinboxMacApp/emptymyinboxMacApp/Assets.xcassets/AppIcon.appiconset",
        root / "Mac/emptymyinboxdesktop/emptymyinboxdesktop/Assets.xcassets/AppIcon.appiconset",
    ]

    master = draw_icon(1024)

    for appicon_dir in mac_targets:
        if not appicon_dir.is_dir():
            print(f"skip missing {appicon_dir}", file=sys.stderr)
            continue
        for name, dim in sizes:
            out = master.resize((dim, dim), Image.Resampling.LANCZOS)
            out.save(appicon_dir / name, format="PNG", optimize=True)
        print(f"wrote AppIcon set -> {appicon_dir}")

    # iOS uses distinct filenames per Contents.json
    ios_sizes: list[tuple[str, int]] = [
        ("40.png", 40),
        ("60.png", 60),
        ("29.png", 29),
        ("58.png", 58),
        ("87.png", 87),
        ("80.png", 80),
        ("120.png", 120),
        ("57.png", 57),
        ("114.png", 114),
        ("180.png", 180),
        ("152.png", 152),
        ("167.png", 167),
        ("1024.png", 1024),
    ]
    ios_dir = root / "iOS/emptyMyInbox/emptyMyInbox/Assets.xcassets/AppIcon.appiconset"
    if ios_dir.is_dir():
        for name, dim in ios_sizes:
            out = master.resize((dim, dim), Image.Resampling.LANCZOS)
            out.save(ios_dir / name, format="PNG", optimize=True)
        # Remove any stray Mac-named files from older runs
        for p in ios_dir.glob("AppIcon*.png"):
            p.unlink()
        print(f"wrote AppIcon set -> {ios_dir}")

    # In-app Logo (1x universal — used by LogoView)
    for logo_dir in [
        root / "Mac/emptymyinboxMacApp/emptymyinboxMacApp/Assets.xcassets/Logo.imageset",
        root / "iOS/emptyMyInbox/emptyMyInbox/Assets.xcassets/Logo.imageset",
    ]:
        if not logo_dir.is_dir():
            continue
        logo = master.resize((512, 512), Image.Resampling.LANCZOS)
        logo.save(logo_dir / "Logo.png", format="PNG", optimize=True)
        print(f"wrote Logo.png -> {logo_dir}")


if __name__ == "__main__":
    main()
