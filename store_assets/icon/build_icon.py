#!/usr/bin/env python3
"""Finishes the Sides app icon from the OpenArt-generated mark (pure Pillow).

The mark: a newspaper front page, the pale slate one in front, with a violet
sheet fanned out behind it on the left and an orange sheet on the right. A
stranger sees "newspaper", which says news. The three sheets in the three lean
colours say "Sides": the same news, seen from several sides. Raw artwork and
prompts are in openart/. The full record is the "Generated artwork" table in
../BRAND.md.

The model draws artwork only. This script does the rest, deterministically:
  1. Key the mark off the model's flat background. Every pixel is snapped to the
     nearest exact brand colour (slate, violet or orange) with an alpha taken from
     its position between the background and that colour, so edges stay
     anti-aliased and the palette is exact. The dark headline and text bars inside
     the page become holes, so the plate shows through as the "ink".
  2. Clip the small corner fragments the model left poking out above and below
     the front page. Only the two side wings of the back sheets stay.
  3. Composite and export every layer.

No tick, badge, seal, rosette, laurel, ribbon or star (house-facts section 29).
No text: the bars are abstract.

Outputs, in this folder unless noted:
  icon_master.png      1024 x 1024 opaque RGB, full-bleed plate (iOS + legacy Android)
  icon_foreground.png  1024 x 1024 transparent, mark inside the adaptive safe zone
  (adaptive background is the solid colour PLATE_FLAT, set in pubspec.yaml)
  icon_monochrome.png  white mark on transparent (Android 13 themed icon)
  icon_mark.png        tight transparent mark, for the feature graphic
  ../icon_512.png      Play hi-res icon (512 x 512, opaque RGB)
  preview_180/120/48.png, preview_adaptive.png  proofs -- look at them
"""

import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "openart", "r2_fanned.png")   # chosen OpenArt output
C = 1024
SS = 4

PLATE_TOP = (0x1D, 0x31, 0x3A)     # #1D313A
PLATE_BOTTOM = (0x0F, 0x1C, 0x22)  # #0F1C22
PLATE_FLAT = "#15252C"             # adaptive background, launch colour

SLATE = (0xC3, 0xCD, 0xD3)         # front page (centre)
VIOLET = (0x8F, 0x63, 0xD2)        # left sheet
ORANGE = (0xE8, 0x91, 0x4A)        # right sheet
INKS = (SLATE, VIOLET, ORANGE)

MASTER_WIDTH = 0.78                # mark width as a share of the master canvas
# Adaptive foreground: flutter_launcher_icons insets it 16% per side, so the
# 1024 canvas spans 68% of the 108 dp layer (73.44 dp). The mask-safe circle is
# 66 dp across: keep the mark's farthest opaque pixel at <= 30.5 dp from centre.
FG_SAFE_DP = 30.0
MONO_ALPHA = {SLATE: 1.0, VIOLET: 0.62, ORANGE: 0.62}


def background(img):
    """Median colour of the outer 16 px frame: the model's flat background."""
    w, h = img.size
    px = img.load()
    samples = [px[x, y] for y in range(0, h, 4) for x in range(0, w, 4)
               if x < 16 or y < 16 or x >= w - 16 or y >= h - 16]
    return tuple(sorted(s[i] for s in samples)[len(samples) // 2] for i in range(3))


def key(img, bg):
    """RGBA mark in exact brand colours, plus a label image (which ink, by index)."""
    w, h = img.size
    out = Image.new("RGBA", (w, h))
    label = Image.new("L", (w, h), 0)
    src = (img.get_flattened_data() if hasattr(img, "get_flattened_data")
           else img.getdata())
    vecs = [tuple(c[i] - bg[i] for i in range(3)) for c in INKS]
    lens = [sum(v * v for v in vec) for vec in vecs]
    rgba, labs = [], []
    for p in src:
        d = (p[0] - bg[0], p[1] - bg[1], p[2] - bg[2])
        best, best_err, best_t = None, 1e18, 0.0
        for i, (vec, ln) in enumerate(zip(vecs, lens)):
            t = (d[0] * vec[0] + d[1] * vec[1] + d[2] * vec[2]) / ln
            t = min(1.0, max(0.0, t))
            err = sum((d[k] - t * vec[k]) ** 2 for k in range(3))
            if err < best_err:
                best, best_err, best_t = i, err, t
        # Flatten the model's slight texture: near-background is clear,
        # near-ink is solid, the anti-aliased edge in between is ramped.
        a = min(1.0, max(0.0, (best_t - 0.12) / 0.70))
        rgba.append(INKS[best] + (round(a * 255),))
        labs.append(best + 1 if a > 0 else 0)
    out.putdata(rgba)
    label.putdata(labs)
    return out, label


def bbox_of(label, ink_index, alpha):
    """Bounding box of solid pixels of one ink."""
    w, h = label.size
    lp, ap = label.load(), alpha.load()
    xs, ys = [], []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if lp[x, y] == ink_index + 1 and ap[x, y] > 200:
                xs.append(x)
                ys.append(y)
    return min(xs), min(ys), max(xs), max(ys)


def clip_fragments(mark, label):
    """Clear everything above the front page's top edge and below its bottom.

    The model let the back sheets' corners poke out there as small triangles;
    the wings beside the page are all the back sheets need to show."""
    alpha = mark.getchannel("A")
    _, top, _, bottom = bbox_of(label, 0, alpha)
    d = ImageDraw.Draw(alpha)
    w, h = mark.size
    d.rectangle([0, 0, w, top - 2], fill=0)
    d.rectangle([0, bottom + 3, w, h], fill=0)
    mark.putalpha(alpha)
    return mark


def max_radius(mark):
    """Farthest visible pixel from the mark's centre, in the mark's own pixels."""
    w, h = mark.size
    ap = mark.getchannel("A").load()
    cx, cy = w / 2, h / 2
    r = 0.0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if ap[x, y] > 8:
                r = max(r, math.hypot(x - cx, y - cy))
    return r


def plate():
    img = Image.new("RGB", (C, C))
    d = ImageDraw.Draw(img)
    for y in range(C):
        t = y / (C - 1)
        d.line([(0, y), (C, y)],
               fill=tuple(round(a + (b - a) * t) for a, b in zip(PLATE_TOP, PLATE_BOTTOM)))
    return img


def placed(mark, scale):
    """Mark scaled and centred on a transparent 1024 canvas."""
    w, h = round(mark.width * scale), round(mark.height * scale)
    m = mark.resize((w, h), Image.LANCZOS)
    canvas = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    canvas.alpha_composite(m, ((C - w) // 2, (C - h) // 2))
    return canvas


def monochrome(mark, label_tight):
    """White mark; the back sheets lighter so the three sheets stay distinct."""
    lp = label_tight.load()
    out = Image.new("RGBA", mark.size, (0, 0, 0, 0))
    op, mp = out.load(), mark.load()
    for y in range(mark.height):
        for x in range(mark.width):
            a = mp[x, y][3]
            if a:
                ink = INKS[lp[x, y] - 1] if lp[x, y] else SLATE
                op[x, y] = (255, 255, 255, round(a * MONO_ALPHA[ink]))
    return out


def main():
    p = lambda n: os.path.join(HERE, n)

    raw = Image.open(RAW).convert("RGB")
    bg = background(raw)
    mark, label = key(raw, bg)
    mark = clip_fragments(mark, label)
    box = mark.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    mark, label = mark.crop(box), label.crop(box)
    mark.save(p("icon_mark.png"))

    # Master + Play hi-res
    master = plate()
    master_scale = MASTER_WIDTH * C / mark.width
    master.paste(placed(mark, master_scale), (0, 0), placed(mark, master_scale))
    master.save(p("icon_master.png"))             # RGB: no alpha channel
    master.resize((512, 512), Image.LANCZOS).save(os.path.join(HERE, "..", "icon_512.png"))

    # Adaptive foreground + themed icon, same geometry
    r = max_radius(mark)
    fg_scale = (FG_SAFE_DP / (0.68 * 108) * C) / r
    placed(mark, fg_scale).save(p("icon_foreground.png"))
    placed(monochrome(mark, label), fg_scale).save(p("icon_monochrome.png"))

    # ---- proofs
    for s in (180, 120, 48):
        master.resize((s, s), Image.LANCZOS).save(p(f"preview_{s}.png"))

    # Round launcher mask: 432 px layer (108 dp x 4), foreground at the 16%
    # inset, masked to the 288 px visible circle (72 dp), 264 px safe circle
    # (66 dp) outlined on top.
    L = 432
    layer = Image.new("RGBA", (L, L), PLATE_FLAT)
    inset = round(L * 0.16)
    layer.alpha_composite(placed(mark, fg_scale).resize((L - 2 * inset,) * 2, Image.LANCZOS),
                          (inset, inset))
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

    fg_r_dp = r * fg_scale / C * 0.68 * 108
    print(f"raw background #{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}; mark {mark.width}x{mark.height}; "
          f"master width {mark.width * master_scale:.0f}/1024 px; "
          f"adaptive farthest point {fg_r_dp:.1f} dp (safe <= 33)")


if __name__ == "__main__":
    main()
