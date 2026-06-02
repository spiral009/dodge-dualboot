#!/usr/bin/env bash
# PC-side helper: turn an official stock OTA/payload into the layout DualBootKit expects.
# Needs: payload-dumper-go (or update_payload), simg2img, and the OEM's OZIP->ZIP if applicable.
#   ./extract-stock-images.sh <payload.bin|OTA.zip> <out_dir>
set -euo pipefail
SRC="${1:?payload.bin or OTA zip}"; OUT="${2:?output dir}"
mkdir -p "$OUT/firmware" "$OUT/super"
echo ">> dumping partitions from $SRC"
if command -v payload-dumper-go >/dev/null; then
  payload-dumper-go -o "$OUT/raw" "$SRC"
else
  echo "install payload-dumper-go (https://github.com/ssut/payload-dumper-go) and re-run"; exit 1
fi
# sort: logical (system/vendor/...) -> super/, the rest (boot/tz/modem/...) -> firmware/
for f in "$OUT"/raw/*.img; do
  b=$(basename "$f")
  case "$b" in
    system.img|system_ext.img|product.img|vendor.img|odm.img|*_dlkm.img) mv "$f" "$OUT/super/";;
    *) mv "$f" "$OUT/firmware/";;
  esac
done
echo ">> done. Copy $OUT/firmware + $OUT/super to the phone at \$KIT_DIR/<os>/ ."
echo ">> my_stock/overlay: mount that partition and copy its CONTENTS to \$KIT_DIR/<os>/my_stock/"
