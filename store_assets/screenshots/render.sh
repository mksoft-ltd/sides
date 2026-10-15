#!/bin/bash
# Frames raw captures (raw/*.png) into store screenshots (out/<target>/<id>.png)
# using specs.json + frame.html. Missing raw files are skipped and listed.
# Usage: store_assets/screenshots/render.sh [target ...]   (default: all targets)
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
python3 - "$CHROME" "$@" <<'PY'
import json, os, subprocess, sys, urllib.parse
from PIL import Image
chrome, wanted = sys.argv[1], sys.argv[2:]
spec = json.load(open("specs.json"))
here = os.getcwd()
for tname, t in spec["targets"].items():
    if wanted and tname not in wanted:
        continue
    os.makedirs(f"out/{tname}", exist_ok=True)
    for shot in spec[t["kind"]]:
        raw = f"{t['raw_dir']}/{shot['raw']}"
        if not os.path.exists(raw):
            print(f"skip {tname}/{shot['id']}: no {raw}"); continue
        q = urllib.parse.urlencode({"src": raw, "w": t["w"], "h": t["h"], "kind": t["kind"],
                                    "theme": shot["theme"], "head": shot["head"], "sub": shot["sub"]})
        out = f"{here}/out/{tname}/{shot['id']}.png"
        subprocess.run([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--force-device-scale-factor=1", f"--window-size={t['w']},{t['h']}",
                        "--allow-file-access-from-files", "--virtual-time-budget=4000",
                        f"--screenshot={out}", f"file://{here}/frame.html?{q}"],
                       check=True, capture_output=True)
        im = Image.open(out).convert("RGB")          # stores want no alpha
        assert im.size == (t["w"], t["h"]), (out, im.size)
        im.save(out)
        print(f"framed {tname}/{shot['id']}")
PY
