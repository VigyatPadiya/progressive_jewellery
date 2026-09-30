"""Render the Progressive Jewellery icon and platform-specific icon sizes.

Requires Pillow: python -m pip install pillow
Run from the repository root: python tools/generate_app_icons.py
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024
SCALE = 4
INK = (36, 35, 33)
GOLD = (176, 138, 72)
PALE_GOLD = (232, 204, 133)
INITIALS = "PJ"


def _font_path() -> Path:
    candidates = (
        Path("C:/Windows/Fonts/georgia.ttf"),
        Path("/Library/Fonts/Georgia.ttf"),
        Path("/usr/share/fonts/truetype/msttcorefonts/Georgia.ttf"),
        Path("/usr/share/fonts/truetype/liberation2/LiberationSerif-Regular.ttf"),
    )
    return next((path for path in candidates if path.exists()), candidates[0])


def make_master_icon() -> Image.Image:
    background = Image.new("RGB", (SIZE, SIZE))
    pixels = background.load()
    for y in range(SIZE):
        for x in range(SIZE):
            distance = math.sqrt((x - SIZE / 2) ** 2 + (y - SIZE * 0.43) ** 2)
            glow = max(0.0, 1.0 - distance / 760)
            pixels[x, y] = tuple(
                min(255, int(base + warmth * glow))
                for base, warmth in zip(INK, (18, 14, 9))
            )

    canvas = background.convert("RGBA").resize(
        (SIZE * SCALE, SIZE * SCALE), Image.Resampling.LANCZOS
    )
    draw = ImageDraw.Draw(canvas)

    def px(value: float) -> int:
        return round(value * SCALE)

    center = px(SIZE / 2)
    draw.ellipse(
        (px(164), px(164), px(860), px(860)),
        outline=(*PALE_GOLD, 255),
        width=px(11),
    )
    draw.ellipse(
        (px(196), px(196), px(828), px(828)),
        outline=(*GOLD, 145),
        width=px(3),
    )

    # A small cut-stone mark sits above the initials.
    diamond = [
        (center, px(239)),
        (px(548), px(275)),
        (center, px(316)),
        (px(476), px(275)),
    ]
    draw.polygon(diamond, fill=(*PALE_GOLD, 255))
    draw.line(
        [(center, px(250)), (center, px(300))],
        fill=(250, 237, 207, 225),
        width=px(3),
    )
    draw.line(
        [(px(487), px(275)), (px(537), px(275))],
        fill=(250, 237, 207, 225),
        width=px(3),
    )

    font = ImageFont.truetype(str(_font_path()), px(350))
    bounds = draw.textbbox((0, 0), INITIALS, font=font, stroke_width=0)
    text_x = center - (bounds[0] + bounds[2]) // 2
    text_y = px(533) - (bounds[1] + bounds[3]) // 2
    draw.text(
        (text_x + px(3), text_y + px(5)),
        INITIALS,
        font=font,
        fill=(0, 0, 0, 115),
        stroke_width=0,
    )
    draw.text(
        (text_x, text_y),
        INITIALS,
        font=font,
        fill=(*PALE_GOLD, 255),
        stroke_width=0,
    )

    # Four fine rays echo the sparkle used in the in-app brand mark.
    star_x, star_y, ray = px(744), px(385), px(19)
    draw.line(
        [(star_x, star_y - ray), (star_x, star_y + ray)],
        fill=(*PALE_GOLD, 220),
        width=px(4),
    )
    draw.line(
        [(star_x - ray, star_y), (star_x + ray, star_y)],
        fill=(*PALE_GOLD, 220),
        width=px(4),
    )
    draw.line(
        [(star_x - px(13), star_y - px(13)), (star_x + px(13), star_y + px(13))],
        fill=(*PALE_GOLD, 190),
        width=px(3),
    )
    draw.line(
        [(star_x - px(13), star_y + px(13)), (star_x + px(13), star_y - px(13))],
        fill=(*PALE_GOLD, 190),
        width=px(3),
    )

    return canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS).convert("RGB")


def write_svg_source() -> None:
    ink = "#%02x%02x%02x" % INK
    gold = "#%02x%02x%02x" % GOLD
    pale_gold = "#%02x%02x%02x" % PALE_GOLD
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <radialGradient id="background" cx="50%" cy="43%" r="72%">
      <stop offset="0" stop-color="#38332a" />
      <stop offset="1" stop-color="{ink}" />
    </radialGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{pale_gold}" />
      <stop offset="0.52" stop-color="{gold}" />
      <stop offset="1" stop-color="{pale_gold}" />
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#background)" />
  <circle cx="512" cy="512" r="348" fill="none" stroke="url(#gold)" stroke-width="11" />
  <circle cx="512" cy="512" r="316" fill="none" stroke="{gold}" stroke-opacity="0.56" stroke-width="3" />
  <path d="M512 239 548 275 512 316 476 275Z" fill="url(#gold)" />
  <path d="M512 250v50M487 275h50" stroke="#f5e6c3" stroke-linecap="round" stroke-opacity="0.82" stroke-width="3" />
  <text x="512" y="670" text-anchor="middle" fill="{pale_gold}" font-family="Georgia, serif" font-size="350" letter-spacing="-24">{INITIALS}</text>
  <path d="M744 366v38m-19-19h38m-31-13 26 26m0-26-26 26" stroke="{pale_gold}" stroke-linecap="round" stroke-width="4" />
</svg>
'''
    (ROOT / "assets/brand/progressive_jewellery_icon.svg").write_text(
        svg, encoding="utf-8"
    )


def save_icon(master: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    master.resize((size, size), Image.Resampling.LANCZOS).save(path, "PNG")


def sizes_from_catalog(catalog: Path) -> dict[str, int]:
    data = json.loads(catalog.read_text(encoding="utf-8"))
    sizes = {}
    for entry in data["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        points = float(entry["size"].split("x")[0])
        scale = float(entry.get("scale", "1x").removesuffix("x"))
        sizes[filename] = max(1, round(points * scale))
    return sizes


def main() -> None:
    master = make_master_icon()
    write_svg_source()
    save_icon(master, ROOT / "assets/brand/progressive_jewellery_icon.png", SIZE)

    android_sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, size in android_sizes.items():
        save_icon(
            master,
            ROOT / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png",
            size,
        )

    for platform in ("ios", "macos"):
        catalog = ROOT / platform / "Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"
        for filename, size in sizes_from_catalog(catalog).items():
            save_icon(master, catalog.parent / filename, size)

    for size in (192, 512):
        save_icon(master, ROOT / f"web/icons/Icon-{size}.png", size)
        save_icon(master, ROOT / f"web/icons/Icon-maskable-{size}.png", size)
    save_icon(master, ROOT / "web/icons/favicon.png", 64)
    save_icon(master, ROOT / "web/favicon.png", 64)

    windows_icon = ROOT / "windows/runner/resources/app_icon.ico"
    windows_icon.parent.mkdir(parents=True, exist_ok=True)
    master.save(windows_icon, format="ICO", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


if __name__ == "__main__":
    main()
