#!/data/adb/ksu/bin/busybox sh
# Bind ColorOS my_stock (extracted INSIDE coloros_data.img) into place.
# Headless: lives in /data/adb/post-fs-data.d/, NOT a visible KSU module.
BB=/data/adb/ksu/bin/busybox
LOG=/data/coloros_restore.log
{
echo "[restore] bind extracted my_stock (inside coloros_data.img); my_preload dropped"
SRC=/data/coloros_mystock
if [ -d "$SRC" ]; then
  $BB mkdir -p /mnt/vendor/my_stock /my_stock
  $BB mount -o bind "$SRC" /mnt/vendor/my_stock && \
  $BB mount -o bind /mnt/vendor/my_stock /my_stock && echo "my_stock bound OK" || echo "my_stock bind FAIL"
else echo "SRC missing"; fi
echo "--- mounts ---"; $BB mount | $BB grep -E "my_stock"
} > "$LOG" 2>&1
