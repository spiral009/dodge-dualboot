#!/usr/bin/env bash
# Obtain ColorOS images the LEGAL way: pull the OFFICIAL OTA (you supply the URL/file
# from OPPO/OnePlus servers - nothing proprietary is hosted by this project), extract,
# and HARD-GATE on anti-rollback so you can't flash firmware that advances the fuse.
#
#   ./get-coloros.sh <OTA.zip|payload.bin|local.ozip|URL> <out_dir> [--device-arb N]
#
# --device-arb N = your phone's CURRENT fused ARB index (read it with arbscan.py on a
#   dump of your live xbl_config_a). Default 0 (fresh dodge). Firmware with ARB > N is
#   REFUSED, because flashing it permanently raises the fuse and can brick downgrades.
set -euo pipefail
SRC="${1:?OTA url/zip/payload/ozip}"; OUT="${2:?out dir}"; DEV_ARB=0
[ "${3:-}" = "--device-arb" ] && DEV_ARB="${4:?N}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT/firmware" "$OUT/super" "$OUT/raw"

case "$SRC" in
  http*://*) echo ">> downloading official OTA"; curl -L -o "$OUT/ota.bin" "$SRC"; SRC="$OUT/ota.bin";;
esac
case "$SRC" in
  *.ozip) command -v ozipdecrypt >/dev/null || { echo "need ozipdecrypt (pip install ozipdecrypt)"; exit 1; }
          ozipdecrypt "$SRC"; SRC="${SRC%.ozip}.zip";;
esac
echo ">> extracting images"
if command -v payload-dumper-go >/dev/null; then payload-dumper-go -o "$OUT/raw" "$SRC"
elif unzip -l "$SRC" >/dev/null 2>&1; then unzip -o "$SRC" -d "$OUT/raw" >/dev/null
else echo "unknown package; provide payload.bin / OTA.zip / .ozip"; exit 1; fi

# ---- ARB GATE ----
XBL="$(ls "$OUT"/raw/xbl_config*.img "$OUT"/raw/xbl*.img 2>/dev/null | head -1 || true)"
if [ -n "$XBL" ] && command -v python3 >/dev/null; then
  echo ">> ARB check (device fuse = $DEV_ARB):"
  ARB=$(python3 "$HERE/arbscan.py" "$XBL" | awk '/ARB index/{print $NF}' | tail -1)
  echo "   firmware ARB index = ${ARB:-unknown}"
  if [ -n "${ARB:-}" ] && [ "$ARB" -gt "$DEV_ARB" ] 2>/dev/null; then
    echo "!! REFUSING: firmware ARB ($ARB) > device fuse ($DEV_ARB). Flashing it would"
    echo "!! permanently raise anti-rollback and can brick. Pick an older ColorOS build"
    echo "!! (dodge: <= 16.0.2.403 = ARB 0; ARB advances at 16.0.3.50x)."
    exit 1
  fi
  echo "   OK: ARB-safe (<= device fuse)."
  [ -n "${ARB:-}" ] && { echo "$ARB" > "$OUT/firmware/.arb_index"; echo "   stamped firmware/.arb_index=$ARB (cos2b.sh reads this offline in recovery)"; }
else
  echo "!! could not auto-verify ARB (no xbl/python). Verify manually with arbscan.py before flashing."
fi

echo ">> sorting into kit layout"
for f in "$OUT"/raw/*.img; do b=$(basename "$f"); case "$b" in
  system.img|system_ext.img|product.img|vendor.img|odm.img|*_dlkm.img) mv -f "$f" "$OUT/super/";;
  *) mv -f "$f" "$OUT/firmware/";; esac; done
echo ">> done. firmware/ + super/ ready. For my_stock: mount that partition and copy its"
echo ">> CONTENTS into \$KIT_DIR/coloros/my_stock/ (then the kit extracts it into the loopback)."
