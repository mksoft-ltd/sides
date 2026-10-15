#!/usr/bin/env python3
"""Builds the Sides app icon from primitives (Pillow, drawn at 4x, LANCZOS down).

The mark: one cube seen from the corner, so three faces show at once and each
face is a different side of the same object -- "one story, every angle". The
faces are pulled slightly apart along their own normals, leaving a Y-shaped
seam, so the three sides read as distinct at 48 px.

Face colours come from the in-app lean palette (lib/core/theme/app_theme.dart),
in their positions: violet face on the left, orange face on the right, slate
face on top between them. Equal areas: no side is bigger than another.

No tick, badge, seal, rosette, laurel, ribbon or star (house-facts section 29).

Outputs (all 1024 x 1024 unless noted), in this folder:
  icon_master.png      opaque, full-bleed plate -- iOS + legacy Android source
  icon_foreground.png  transparent, mark scaled for the adaptive 16% inset
  (adaptive background is the solid colour PLATE_FLAT, set in pubspec.yaml)
  icon_monochrome.png  white mark on transparent (Android 13 themed icon)
  icon_master.svg      vector copy of the master for reuse in HTML art
  ../icon_512.png      Play hi-res icon (512 x 512, opaque)
  preview_180/120/48.png, preview_adaptive.png  proofs -- look at them
"""

import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SS = 4                         # supersampling factor
C = 1024                       # canvas

PLATE_TOP = (0x1D, 0x31, 0x3A)     # #1D313A
PLATE_BOTTOM = (0x0F, 0x1C, 0x22)  # #0F1C22
PLATE_FLAT = "#15252C"             # adaptive background, launch colour

FACE_TOP = (0xC3, 0xCD, 0xD3)      # centre slate, lit
FACE_LEFT = (0x8F, 0x63, 0xD2)     # left violet
FACE_RIGHT = (0xE8, 0x91, 0x4A)    # right orange

R = 340.0          # hexagon circumradius at master scale
GAP = 18.0         # how far each face is pulled out along its normal
COS30 = math.cos(math.radians(30))


def faces(scale=1.0, cx=C / 2, cy=C / 2):
    """Three quads (top, left, right) in canvas units."""
    r = R * scale
    g = GAP * scale
    top = (0, -r)
    ur = (r * COS30, -r / 2)
    lr = (r * COS30, r / 2)
    bot = (0, r)
    ll = (-r * COS30, r / 2)
    ul = (-r * COS30, -r / 2)
    o = (0, 0)
    quads = {
        "top": ([top, ur, o, ul], (0, -1)),
        "left": ([ul, o, bot, ll], (-COS30, 0.5)),
        "right": ([o, ur, lr, bot], (COS30, 0.5)),
    }
    out = {}
    for k, (pts, (nx, ny)) in quads.items():
        out[k] = [(cx + x + nx * g, cy + y + ny * g) for x, y in pts]
    return out


def max_radius(scale=1.0):
    return max(math.hypot(x - C / 2, y - C / 2)
               for q in faces(scale).values() for x, y in q)


def draw_mark(img, scale, colours):
    d = ImageDraw.Draw(img)
    for k, pts in faces(scale).items():
        d.polygon([(x * SS, y * SS) for x, y in pts], fill=colours[k])


def plate():
    big = Image.new("RGB", (C * SS, C * SS))
    d = ImageDraw.Draw(big)
    for y in range(C * SS):
        t = y / (C * SS - 1)
        d.line([(0, y), (C * SS, y)],
               fill=tuple(round(a + (b - a) * t) for a, b in zip(PLATE_TOP, PLATE_BOTTOM)))
    return big


def down(img, size=C):
    return img.resize((size, size), Image.LANCZOS)


COLOURS = {"top": FACE_TOP, "left": FACE_LEFT, "right": FACE_RIGHT}

# Optical centring: the cube's silhouette is symmetric, so the geometric centre
# is also the visual one; no nudge needed.
MASTER_SCALE = 1.0

# Adaptive foreground: flutter_launcher_icons insets it 16% per side, so the
# 1024 canvas spans 68% of the 108 dp layer (73.44 dp). The mask-safe circle is
# 66 dp across; keep the mark's farthest point at <= 30.5 dp from the centre.
FG_SAFE_DP = 28.5
FG_SCALE = (FG_SAFE_DP / (0.68 * 108) * C) / max_radius(1.0)


def svg_master():
    def poly(pts, fill):
        return '<polygon points="{}" fill="#{:02X}{:02X}{:02X}"/>'.format(
            " ".join(f"{x:.1f},{y:.1f}" for x, y in pts), *fill)
    f = faces(MASTER_SCALE)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{C}" height="{C}" viewBox="0 0 {C} {C}">
  <defs><linearGradient id="p" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#{PLATE_TOP[0]:02X}{PLATE_TOP[1]:02X}{PLATE_TOP[2]:02X}"/>
    <stop offset="1" stop-color="#{PLATE_BOTTOM[0]:02X}{PLATE_BOTTOM[1]:02X}{PLATE_BOTTOM[2]:02X}"/>
  </linearGradient></defs>
  <rect width="{C}" height="{C}" fill="url(#p)"/>
  {poly(f['top'], FACE_TOP)}
  {poly(f['left'], FACE_LEFT)}
  {poly(f['right'], FACE_RIGHT)}
</svg>
"""


def svg_mark():
    """Mark only, transparent, tight viewBox -- for the feature graphic."""
    f = faces(1.0, cx=0, cy=0)
    m = max(abs(v) for q in f.values() for p in q for v in p)
    def poly(pts, fill):
        return '<polygon points="{}" fill="#{:02X}{:02X}{:02X}"/>'.format(
            " ".join(f"{x:.1f},{y:.1f}" for x, y in pts), *fill)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-m:.1f} {-m:.1f} {2*m:.1f} {2*m:.1f}">
  {poly(f['top'], FACE_TOP)}
  {poly(f['left'], FACE_LEFT)}
  {poly(f['right'], FACE_RIGHT)}
</svg>
"""


def main():
    p = lambda n: os.path.join(HERE, n)

    master = plate()
    draw_mark(master, MASTER_SCALE, COLOURS)
    master = down(master)
    master.save(p("icon_master.png"))            # RGB: no alpha channel
    master.resize((512, 512), Image.LANCZOS).save(os.path.join(HERE, "..", "icon_512.png"))

    fg = Image.new("RGBA", (C * SS, C * SS), (0, 0, 0, 0))
    draw_mark(fg, FG_SCALE, {k: v + (255,) for k, v in COLOURS.items()})
    down(fg).save(p("icon_foreground.png"))


    # Themed icon: one tint, so the faces separate by alpha as well as the seam.
    mono = Image.new("RGBA", (C * SS, C * SS), (0, 0, 0, 0))
    draw_mark(mono, FG_SCALE, {"top": (255, 255, 255, 255),
                               "left": (255, 255, 255, 170),
                               "right": (255, 255, 255, 110)})
    down(mono).save(p("icon_monochrome.png"))

    with open(p("icon_master.svg"), "w") as fh:
        fh.write(svg_master())
    with open(p("icon_mark.svg"), "w") as fh:
        fh.write(svg_mark())

    # ---- proofs
    for s in (180, 120, 48):
        master.resize((s, s), Image.LANCZOS).save(p(f"preview_{s}.png"))

    # Round launcher mask: 432 px layer (108 dp x 4), foreground at the 16%
    # inset, masked to the 288 px visible circle (72 dp), 264 px safe circle
    # (66 dp) outlined on top.
    L = 432
    layer = Image.new("RGBA", (L, L), PLATE_FLAT)
    inset = round(L * 0.16)
    layer.alpha_composite(down(fg, L - 2 * inset), (inset, inset))
    mask = Image.new("L", (L * SS, L * SS), 0)
    ImageDraw.Draw(mask).ellipse([(L - 288) / 2 * SS, (L - 288) / 2 * SS,
                                  (L + 288) / 2 * SS, (L + 288) / 2 * SS], fill=255)
    mask = mask.resize((L, L), Image.LANCZOS)
    proof = Image.new("RGBA", (L, L), (255, 255, 255, 255))
    proof.paste(layer, (0, 0), mask)
    d = ImageDraw.Draw(proof)
    d.ellipse([(L - 264) / 2, (L - 264) / 2, (L + 264) / 2, (L + 264) / 2],
              outline=(255, 0, 80, 255), width=1)
    proof.save(p("preview_adaptive.png"))

    fg_r_dp = max_radius(FG_SCALE) / C * 0.68 * 108
    print(f"master mark radius {max_radius(1.0):.0f}/512 px; "
          f"adaptive scale {FG_SCALE:.3f}, farthest point {fg_r_dp:.1f} dp (safe <= 33)")


if __name__ == "__main__":
    main()
