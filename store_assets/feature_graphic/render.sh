#!/bin/bash
# Renders the Play feature graphic (1024 x 500, opaque) and a crop proof.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1024,500 --allow-file-access-from-files --virtual-time-budget=3000 \
  --screenshot="$PWD/feature_graphic_rgba.png" "file://$PWD/feature_graphic.html" >/dev/null 2>&1
# Play wants a 24-bit PNG or JPEG: flatten, then write the crop proof (outer
# 100 px shaded -- Play crops the graphic on some surfaces).
python3 - <<'PY'
from PIL import Image, ImageDraw
im = Image.open("feature_graphic_rgba.png").convert("RGB")
assert im.size == (1024, 500), im.size
im.save("../feature_graphic.png")
pr = im.convert("RGBA"); sh = Image.new("RGBA", im.size, (255, 0, 80, 70))
m = Image.new("L", im.size, 255); ImageDraw.Draw(m).rectangle([100, 100, 923, 399], fill=0)
pr.paste(sh, (0, 0), m); pr.convert("RGB").save("proof_crop.png")
PY
rm feature_graphic_rgba.png
echo "rendered: store_assets/feature_graphic.png  proof: feature_graphic/proof_crop.png"
