#!/usr/bin/env python3
"""Capture the App Store screenshots on an iOS simulator, host-side.

`binding.takeScreenshot` returns the launch screen on iOS simulators, so the
harness prints `SIDES_SHOT_READY <name>` and waits; this script grabs the
simulator screen with `xcrun simctl io` and drops `<name>.done` to release it.

  scripts/publish/capture_ios.py <udid> <out_dir> [expected_count]

Checks afterwards: exit status, count, every PNG distinct (md5), one size.
"""
import hashlib, os, pathlib, subprocess, sys, struct, time
from PIL import Image

udid, out = sys.argv[1], pathlib.Path(sys.argv[2]).resolve()
expected = int(sys.argv[3]) if len(sys.argv) > 3 else None
root = pathlib.Path(__file__).resolve().parents[2]
hand = root / "build" / "screenshot_handshake" / udid
hand.mkdir(parents=True, exist_ok=True)
out.mkdir(parents=True, exist_ok=True)
for f in hand.glob("*.done"):
    f.unlink()

def sh(*a):
    subprocess.run(a, check=True)

subprocess.run(["xcrun", "simctl", "boot", udid])  # already booted is fine
sh("xcrun", "simctl", "bootstatus", udid, "-b")
sh("xcrun", "simctl", "ui", udid, "appearance", "light")
sh("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41",
   "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
   "--cellularMode", "active", "--cellularBars", "4",
   "--batteryState", "charged", "--batteryLevel", "100")

cmd = ["flutter", "drive", "--driver=test_driver/integration_test.dart",
       "--target=integration_test/screenshots_test.dart", "-d", udid,
       f"--dart-define=SCREENSHOT_HOST_DIR={hand}",
       "--dart-define=SCREENSHOT_PRICE=£2.99"]
proc = subprocess.Popen(cmd, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
taken = []
problems_early = []
for line in proc.stdout:
    sys.stdout.write(line)
    if "SIDES_SHOT_READY " in line:
        name = line.split("SIDES_SHOT_READY ", 1)[1].strip()
        dest = out / f"{name}.png"
        # SpringBoard sometimes draws the Dynamic Island over a frame (pure
        # black pill at the top centre). Retake until it is gone.
        for attempt in range(8):
            sh("xcrun", "simctl", "io", udid, "screenshot", "--type=png", str(dest))
            im = Image.open(dest).convert("RGB")
            w, h = im.size
            island = w / h < 0.6 and all(im.getpixel((w // 2 + dx, round(h * 0.033))) == (0, 0, 0)
                                   for dx in (-60, 0, 60))
            if not island:
                break
            print(f"{name}: Dynamic Island in frame, retaking", flush=True)
            time.sleep(2)
        else:
            problems_early.append(f"{name}: Dynamic Island never cleared")
        (hand / f"{name}.done").touch()
        taken.append(dest)
        print(f"captured {dest}", flush=True)
rc = proc.wait()

def size(p):
    return struct.unpack(">II", p.read_bytes()[16:24])

problems = list(problems_early)
if rc != 0:
    problems.append(f"flutter drive exited {rc}")
if expected is not None and len(taken) != expected:
    problems.append(f"{len(taken)} captures, expected {expected}")
md5s = {hashlib.md5(p.read_bytes()).hexdigest() for p in taken}
if len(md5s) != len(taken):
    problems.append("duplicate captures (md5)")
sizes = {size(p) for p in taken}
if len(sizes) > 1:
    problems.append(f"mixed sizes {sizes}")
print(f"{len(taken)} captures, sizes {sizes}")
if problems:
    sys.exit("CAPTURE FAILED: " + "; ".join(problems))
