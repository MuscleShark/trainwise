"""Builds the IronSage logo as outlined SVG (no font needed to display it).

IRON over SAGE in Barlow Condensed ExtraBold, both lines exactly the same width (the
narrower word gets extra letter-spacing), with a loaded barbell underneath as the base.

usage: python3 -I make_logo.py FONT.ttf OUT_DIR
"""

import sys
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

font_path, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
out_dir.mkdir(parents=True, exist_ok=True)

font = TTFont(font_path)
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()
hmtx = font["hmtx"]


def glyph(ch):
    name = cmap[ord(ch)]
    pen = SVGPathPen(glyphs)
    glyphs[name].draw(pen)
    bounds = BoundsPen(glyphs)
    glyphs[name].draw(bounds)
    return name, pen.getCommands(), bounds.bounds, hmtx[name][0]


def ink(word):
    """Ink width of a word set with default spacing, plus its first glyph's left bearing."""
    x, left, right = 0, None, None
    for ch in word:
        _, _, (x0, _, x1, _), adv = glyph(ch)
        left = x + x0 if left is None else left
        right = x + x1
        x += adv
    return right - left, left


def lockup(width, colors, cx=0, top=0):
    """The logo as SVG elements, `width` wide, centered on cx, starting at `top`.

    Returns (elements, height)."""
    widest = max(ink("IRON")[0], ink("SAGE")[0])
    k = width / widest  # font units -> output units
    cap = glyph("I")[2][3] * k
    lead, plate_h, gap = cap * 0.28, cap * 0.62, cap * 0.42
    height = cap + lead + cap + gap + plate_h
    x0 = cx - width / 2
    out = []

    def line(word, baseline):
        natural, first_left = ink(word)
        spacing = (width / k - natural) / (len(word) - 1)
        x = -first_left
        for ch in word:
            _, d, _, adv = glyph(ch)
            out.append(
                f'<path transform="translate({x0 + x * k:.3f} {baseline:.3f}) scale({k:.6f} {-k:.6f})" '
                f'd="{d}" fill="{colors["ink"]}"/>'
            )
            x += adv + spacing

    y1 = top + cap
    y2 = y1 + lead + cap
    line("IRON", y1)
    line("SAGE", y2)

    by = y2 + gap + plate_h / 2
    ph = plate_h
    sleeve, sleeve_h = ph * 0.16, ph * 0.3
    pw, pw2, ph2 = ph * 0.26, ph * 0.26 * 0.8, ph * 0.74
    collar, collar_h, bar = ph * 0.12, ph * 0.42, ph * 0.14
    space = ph * 0.035
    inner = sleeve + pw + space + pw2 + space + collar

    def rect(x, w, h, fill, rx):
        out.append(
            f'<rect x="{x:.3f}" y="{by - h / 2:.3f}" width="{w:.3f}" height="{h:.3f}" '
            f'rx="{rx:.3f}" fill="{fill}"/>'
        )

    rect(x0 + inner - 0.5, width - 2 * inner + 1, bar, colors["bar"], 0)
    for side in (0, 1):
        def at(offset, w):
            return x0 + width - offset - w if side else x0 + offset

        rect(at(0, sleeve + 0.5), sleeve + 0.5, sleeve_h, colors["metal"], ph * 0.03)
        rect(at(sleeve, pw), pw, ph, colors["plate"], ph * 0.05)
        rect(at(sleeve + pw + space, pw2), pw2, ph2, colors["plate"], ph * 0.05)
        rect(at(sleeve + pw + space + pw2 + space, collar), collar, collar_h, colors["metal"], ph * 0.025)
    return out, height


LIGHT = {"ink": "#111111", "plate": "#E2412D", "bar": "#3A3D42", "metal": "#8A9097"}
DARK = {"ink": "#F4EFE6", "plate": "#E2412D", "bar": "#D9DDE1", "metal": "#9AA0A6"}
TINTED = {"ink": "#FFFFFF", "plate": "#B8B8B8", "bar": "#8C8C8C", "metal": "#6E6E6E"}


def write(name, size, bg, colors, width_ratio):
    elements, h = lockup(size * width_ratio, colors, cx=size / 2)
    top = (size - h) / 2
    elements, _ = lockup(size * width_ratio, colors, cx=size / 2, top=top)
    background = f'<rect width="{size}" height="{size}" fill="{bg}"/>' if bg else ""
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="0 0 {size} {size}">{background}{"".join(elements)}</svg>\n'
    )
    (out_dir / name).write_text(svg)


# App icons: full-bleed squares (iOS rounds the corners). Same proportions as the preview:
# a 104-unit-wide lockup in a 180-unit tile.
write("app-icon.svg", 1024, "#F4EFE6", LIGHT, 104 / 180)
write("app-icon-dark.svg", 1024, "#111111", DARK, 104 / 180)
write("app-icon-tinted.svg", 1024, "#000000", TINTED, 104 / 180)


# The lockup alone on a transparent background, cropped to its own bounds.
def lockup_only(name, colors):
    width = 400
    elements, h = lockup(width, colors, cx=width / 2)
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{h:.0f}" '
        f'viewBox="0 0 {width} {h:.3f}">{"".join(elements)}</svg>\n'
    )
    (out_dir / name).write_text(svg)


lockup_only("logo.svg", LIGHT)
lockup_only("logo-dark.svg", DARK)
print("wrote", sorted(p.name for p in out_dir.glob("*.svg")))
