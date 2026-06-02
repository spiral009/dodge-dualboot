#!/sbin/sh
# ============================================================
#  AviumUI (_a) REPAIR  -  "stuck locked / no launcher / bootloop"
#  after a ColorOS (_b) trip scrambled the shared TEE/keystore.
#  RUN IN RECOVERY (OrangeFox) ON SLOT _a:
#     adb shell  sh /sdcard/aviumui_fix.sh
#     (or OrangeFox -> Terminal:  sh /sdcard/aviumui_fix.sh)
#  Safe: backs everything up first. Costs only your PIN + some
#  app re-logins. Photos/files/apps are untouched.
# ============================================================
echo "=== AviumUI lock/keystore repair ==="
[ "$(id -u)" != "0" ] && { echo "ERROR: not root - run this in recovery."; exit 1; }

mount | grep -q " /data " || mount /data 2>/dev/null || mount /dev/block/by-name/userdata /data 2>/dev/null
mount | grep -q " /data " || { echo "ERROR: /data not mounted. In OrangeFox: Mount -> Data, then retry."; exit 1; }
[ -d /data/system_de/0 ] || { echo "ERROR: /data/system_de/0 missing (wrong slot?). Abort."; exit 1; }
echo "[ok] /data mounted"

TS="$(date +%Y%m%d_%H%M%S 2>/dev/null)"; [ -z "$TS" ] && TS="manual"
BK=/data/media/0/aviumui_lock_backup_$TS
mkdir -p "$BK/spblob"
cp -a /data/system/locksettings.db* "$BK/" 2>/dev/null
cp -a /data/system_de/0/spblob/. "$BK/spblob/" 2>/dev/null
cp -a /data/misc/keystore/persistent.sqlite "$BK/persistent.sqlite.bak" 2>/dev/null
echo "[ok] backup -> $BK"

rm -f /data/system/locksettings.db /data/system/locksettings.db-journal /data/system/locksettings.db-wal /data/system/locksettings.db-shm
rm -f /data/system_de/0/spblob/*
rm -f /data/misc/keystore/persistent.sqlite /data/misc/keystore/persistent.sqlite-wal /data/misc/keystore/persistent.sqlite-shm
echo "[ok] cleared credential + keystore"

echo "--- verify ---"
echo "  locksettings.db : $(ls /data/system/locksettings.db 2>/dev/null || echo GONE)"
echo "  spblob entries  : $(ls -A /data/system_de/0/spblob/ 2>/dev/null | wc -l)"
echo "  persistent.sqlite: $(ls /data/misc/keystore/persistent.sqlite 2>/dev/null || echo GONE)"
echo
echo "=== DONE. Reboot -> System (slot _a). It boots PASSWORDLESS. ==="
echo "Set a new PIN in Settings. Undo (if ever needed): sh /sdcard/aviumui_restore.sh"
echo "Backup kept at: $BK"
