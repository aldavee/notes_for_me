#!/usr/bin/env python3
"""Generates high-DPI anti-aliased launcher icons for Notes For Me."""

from pathlib import Path
from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parent.parent
RES_DIR = REPO_ROOT / "android" / "app" / "src" / "main" / "res"
ASSETS_ICON_DIR = REPO_ROOT / "assets" / "icon"
WINDOWS_ICO_PATH = REPO_ROOT / "windows" / "runner" / "resources" / "app_icon.ico"


def _lerp_color(c1, c2, t: float):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(4))


def render_background(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (15, 23, 42, 255))
    px = img.load()
    c_top = (15, 23, 42, 255)      # #0F172A Slate 900
    c_mid = (30, 27, 75, 255)      # #1E1B4B Indigo 950
    c_bot = (67, 56, 202, 255)     # #4338CA Indigo 700
    for y in range(size):
        for x in range(size):
            t = (x + y) / max(1, (2 * size - 2))
            if t < 0.55:
                col = _lerp_color(c_top, c_mid, t / 0.55)
            else:
                col = _lerp_color(c_mid, c_bot, (t - 0.55) / 0.45)
            px[x, y] = col

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    pad = int(size * 0.14)
    gdraw.ellipse(
        [pad, pad, size - pad, size - pad],
        fill=(245, 158, 11, 32),  # Warm amber glow
    )
    return Image.alpha_composite(img, glow)


def render_foreground(size: int, full_bleed: bool = False) -> Image.Image:
    ss = 4
    canvas_sz = size * ss
    img = Image.new("RGBA", (canvas_sz, canvas_sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    scale = 1.24 if full_bleed else 1.0

    def pt(v: float) -> float:
        centered = (v - 54.0) * scale + 54.0
        return centered * (canvas_sz / 108.0)

    # Note sheet card with folded corner
    x0, y0, x1, y1 = pt(27), pt(21), pt(81), pt(87)
    fold = pt(67) - x0
    fold_x = x1 - (pt(14) - pt(0))
    fold_y = y0 + (pt(14) - pt(0))
    radius = int(6.0 * scale * (canvas_sz / 108.0))
    stroke_w = max(2, int(2.0 * scale * (canvas_sz / 108.0)))

    # Shadow
    off = max(2, int(2.5 * scale * (canvas_sz / 108.0)))
    draw.rounded_rectangle(
        [x0 + off, y0 + off, x1 + off, y1 + off],
        radius=radius,
        fill=(0, 0, 0, 70),
    )

    # Cream/warm paper body
    paper = (254, 249, 239, 255)
    amber_accent = (245, 158, 11, 255)
    indigo_ink = (49, 46, 129, 255)
    slate_line = (148, 163, 184, 255)

    draw.rounded_rectangle(
        [x0, y0, x1, y1],
        radius=radius,
        fill=paper,
        outline=(251, 191, 36, 255),
        width=stroke_w,
    )

    # Top accent bookmark strip
    strip_h = max(4, int(6.0 * scale * (canvas_sz / 108.0)))
    draw.rounded_rectangle(
        [x0 + stroke_w, y0 + stroke_w, x1 - stroke_w, y0 + strip_h + stroke_w],
        radius=max(2, radius // 2),
        fill=amber_accent,
    )

    # Note lines
    line_w = max(3, int(3.0 * scale * (canvas_sz / 108.0)))
    lines = [
        (35.0, 41.0, 68.0, indigo_ink),
        (35.0, 52.0, 73.0, slate_line),
        (35.0, 62.0, 64.0, slate_line),
        (35.0, 72.0, 56.0, slate_line),
    ]
    for lx0, ly, lx1, col in lines:
        p0 = (pt(lx0), pt(ly))
        p1 = (pt(lx1), pt(ly))
        draw.line([p0, p1], fill=col, width=line_w)
        r = line_w / 2.0
        for p in (p0, p1):
            draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=col)

    # Checkmark badge on bottom-right corner
    bx, by = pt(74.0), pt(75.0)
    br = 10.5 * scale * (canvas_sz / 108.0)
    draw.ellipse(
        [bx - br, by - br, bx + br, by + br],
        fill=(79, 70, 229, 255),
        outline=paper,
        width=max(2, int(2.0 * scale * (canvas_sz / 108.0))),
    )
    cw = max(3, int(2.6 * scale * (canvas_sz / 108.0)))
    c1 = (pt(69.5), pt(75.5))
    c2 = (pt(73.0), pt(79.0))
    c3 = (pt(79.0), pt(71.5))
    draw.line([c1, c2, c3], fill=(255, 255, 255, 255), width=cw, joint="curve")
    for p in (c1, c2, c3):
        r = cw / 2.0
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=(255, 255, 255, 255))

    return img.resize((size, size), Image.Resampling.LANCZOS)


def render_combined_icon(size: int, circular: bool = False) -> Image.Image:
    bg = render_background(size)
    fg = render_foreground(size, full_bleed=True)
    merged = Image.alpha_composite(bg, fg)

    mask = Image.new("L", (size * 4, size * 4), 0)
    mdraw = ImageDraw.Draw(mask)
    if circular:
        pad = int(size * 4 * 0.02)
        mdraw.ellipse([pad, pad, size * 4 - pad, size * 4 - pad], fill=255)
    else:
        pad = int(size * 4 * 0.04)
        rad = int(size * 4 * 0.22)
        mdraw.rounded_rectangle(
            [pad, pad, size * 4 - pad, size * 4 - pad],
            radius=rad,
            fill=255,
        )
    mask = mask.resize((size, size), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(merged, (0, 0), mask)
    return out


def main():
    ASSETS_ICON_DIR.mkdir(parents=True, exist_ok=True)
    master = render_combined_icon(1024, circular=False)
    master.save(ASSETS_ICON_DIR / "app_icon.png", "PNG")

    # Windows multi-size .ico
    WINDOWS_ICO_PATH.parent.mkdir(parents=True, exist_ok=True)
    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    master.save(WINDOWS_ICO_PATH, format="ICO", sizes=ico_sizes)

    densities = {
        "mipmap-mdpi": (48, 108),
        "mipmap-hdpi": (72, 162),
        "mipmap-xhdpi": (96, 216),
        "mipmap-xxhdpi": (144, 324),
        "mipmap-xxxhdpi": (192, 432),
    }

    for folder, (legacy_sz, fg_sz) in densities.items():
        target = RES_DIR / folder
        target.mkdir(parents=True, exist_ok=True)
        render_combined_icon(legacy_sz, circular=False).save(target / "ic_launcher.png", "PNG")
        render_combined_icon(legacy_sz, circular=True).save(target / "ic_launcher_round.png", "PNG")
        render_foreground(fg_sz, full_bleed=False).save(target / "ic_launcher_foreground.png", "PNG")

    print("Generated Notes For Me launcher icons (Android mipmaps, assets/icon/app_icon.png, Windows app_icon.ico).")


if __name__ == "__main__":
    main()
