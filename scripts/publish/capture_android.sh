#!/bin/zsh
# Capture the Play screenshots on an Android emulator through the in-app
# takeScreenshot (Flutter surface only, so no status bar).
#   scripts/publish/capture_android.sh phone|tablet <serial>
# phone  = 1080x2400 @420dpi (411x914 dp), tablet = 2560x1600 @320dpi (1280x800 dp, landscape).
# The wm overrides revert silently (SystemUI restart), so they are asserted right
# before the drive and the PNG sizes are asserted after it.
set -euo pipefail
setopt null_glob extended_glob
kind=$1; serial=$2
ROOT=${0:A:h:h:h}; OUT=$ROOT/store_assets/screenshots/raw_android
ADB=(~/Library/Android/sdk/platform-tools/adb -s $serial)
case $kind in
  phone)  size=1080x2400; dens=420; n=7; glob='(phone_*|iap_review_settings).png' ;;
  tablet) size=2560x1600; dens=320; n=4; glob='ipad_*.png' ;;
  *) echo "phone|tablet"; exit 2 ;;
esac
$ADB shell cmd uimode night no
$ADB shell wm density $dens; $ADB shell wm size $size; sleep 3
# Effective geometry = the Override line if present, else the Physical one.
eff() { $ADB shell wm $1 | tr -d '\r' | awk -F': ' '/Override/{o=$2} /Physical/{p=$2} END{print (o?o:p)}'; }
[[ "$(eff size)" == "$size" ]] || { echo "display size is $(eff size), want $size"; exit 1; }
[[ "$(eff density)" == "$dens" ]] || { echo "density is $(eff density), want $dens"; exit 1; }
mkdir -p $OUT; rm -f $OUT/${~glob} $OUT/iap_review_settings.png
cd $ROOT
SCREENSHOT_DIR=$OUT flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart -d $serial \
  --dart-define=SCREENSHOT_PRICE=£2.99
files=($OUT/${~glob})
[[ ${#files} -eq $n ]] || { echo "expected $n captures, got ${#files}"; exit 1; }
[[ $(md5 -q $files | sort -u | wc -l | tr -d ' ') -eq $n ]] || { echo "duplicate captures"; exit 1; }
want=${size/x/ }
for f in $files; do
  got="$(sips -g pixelWidth -g pixelHeight $f | awk '/pixel/{printf "%s ", $2}')"
  [[ "$got" == "$want " ]] || { echo "$f is $got, want $want"; exit 1; }
done
echo "$kind: $n captures at $size OK"
