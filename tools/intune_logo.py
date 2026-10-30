#!/usr/bin/env python3
"""Make an app's Intune logo: its logo.png on a full-bleed square colored from the logo itself.

Company Portal draws a light gray tile behind app icons, which shows through a transparent logo.
This fills the whole square instead. The background is a deep shade of one of the logo's own
colors: of the logo's main saturated colors (black, white and grays don't count), the darkest
one, because darkening an already-dark color keeps it rich (Python's blue becomes navy), while
darkening a light one turns muddy (yellow becomes olive). It's a radial gradient of that hue,
lighter behind the logo and deeper at the edges, with a soft light halo behind the logo so its
darker parts stay distinct. The logo itself isn't changed.

Needs Pillow (pip install pillow). Writes logo-intune.png next to each logo.png.

Usage:
    python3 tools/intune_logo.py apps/Python/3.15/logo.png [more logo.png files...]
    python3 tools/intune_logo.py --all          every apps/*/*/logo.png
"""
import argparse
import colorsys
import glob
import os

from PIL import Image, ImageFilter

SIZE = 256
LOGO = 184          # the logo's size inside the square
EDGE_L, CENTER_L = 0.13, 0.27   # background lightness at the corners and the middle


def background_hue(logo):
    """(hue, saturation) of the darkest of the logo's main saturated colors."""
    rgba = logo.convert("RGBA")
    pixels = getattr(rgba, "get_flattened_data", rgba.getdata)()   # getdata is deprecated in newer Pillow
    opaque = [px[:3] for px in pixels if px[3] > 200]
    if not opaque:
        return 0.0, 0.0
    strip = Image.new("RGB", (len(opaque), 1))
    strip.putdata(opaque)
    palette_image = strip.quantize(colors=8, method=Image.Quantize.MEDIANCUT)
    palette = palette_image.getpalette()
    counts = palette_image.getcolors() or []
    saturated = []
    for count, index in counts:
        r, g, b = (c / 255 for c in palette[index * 3:index * 3 + 3])
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        if s > 0.3 and 0.12 < l < 0.88:
            saturated.append((count, h, l, s))
    if not saturated:
        return 0.0, 0.0          # a black/white/gray logo: neutral background
    total = sum(c for c, *_ in saturated)
    main = [x for x in saturated if x[0] >= 0.15 * total]
    _, h, _, s = min(main, key=lambda x: x[2])   # the darkest main color
    return h, min(s, 0.75)


def make(path):
    logo = Image.open(path).convert("RGBA")
    h, s = background_hue(logo)

    # Radial gradient from CENTER_L (middle) to EDGE_L (corners) in the chosen hue.
    distance = Image.radial_gradient("L").resize((SIZE, SIZE), Image.BILINEAR)   # 0 middle .. 255 edge
    lightness = [CENTER_L + (EDGE_L - CENTER_L) * min(d / 255 * 1.15, 1) for d in range(256)]
    lut = [colorsys.hls_to_rgb(h, l, s) for l in lightness]
    channels = [distance.point([round(c[i] * 255) for c in lut]) for i in range(3)]
    square = Image.merge("RGB", channels).convert("RGBA")

    inner = logo.copy()
    inner.thumbnail((LOGO, LOGO), Image.LANCZOS)
    offset = ((SIZE - inner.width) // 2, (SIZE - inner.height) // 2)

    # A soft light halo in the logo's shape, so dark parts of the logo stay distinct.
    alpha = Image.new("L", (SIZE, SIZE), 0)
    alpha.paste(inner.getchannel("A"), offset)
    halo = alpha.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(8))
    halo = halo.point(lambda a: a * 0.24)
    square = Image.composite(Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255)), square, halo)

    square.alpha_composite(inner, offset)
    out = os.path.join(os.path.dirname(path), "logo-intune.png")
    square.convert("RGB").save(out, optimize=True)
    r, g, b = (round(c * 255) for c in colorsys.hls_to_rgb(h, (EDGE_L + CENTER_L) / 2, s))
    print(f"{out}: background hue from the logo, about #{r:02x}{g:02x}{b:02x}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logos", nargs="*", help="logo.png files")
    parser.add_argument("--all", action="store_true", help="every apps/*/*/logo.png")
    args = parser.parse_args()
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    logos = sorted(glob.glob(os.path.join(repo, "apps", "*", "*", "logo.png"))) if args.all else args.logos
    if not logos:
        parser.error("name logo.png files, or pass --all")
    for path in logos:
        make(path)


if __name__ == "__main__":
    main()
