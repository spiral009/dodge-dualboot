#!/sbin/sh
# ============================================================
#  UNDO aviumui_fix.sh - restores the lock/keystore from the
#  newest backup (returns _a to its PRE-fix state, i.e. locked).
#  Only needed if you ran the fix by mistake.
#  RUN IN RECOVERY ON SLOT _a:  adb shell sh /sdcard/aviumui_restore.sh
# ============================================================
[ "$(id -u)" != "0" ] && { echo "ERROR: not root."; exit 1; }
mount | grep -q " /data " || mount /data 2>/dev/null || mount /dev/block/by-name/userdata /data 2>/dev/null
mount | grep -q " /data " || { echo "ERROR: /data not mounted."; exit 1; }

BK=$(ls -d /data/media/0/aviumui_lock_backup_* /data/media/0/lock_backup_* 2>/dev/null | sort | tail -1)
[ -d "$BK" ] || { echo "ERROR: no backup found on /sdcard."; exit 1; }
echo "Restoring from: $BK"
cp -a "$BK"/locksettings.db /data/system/ 2>/dev/null
cp -a "$BK"/locksettings.db-journal /data/system/ 2>/dev/null
cp -a "$BK"/spblob/. /data/system_de/0/spblob/ 2>/dev/null
[ -f "$BK/persistent.sqlite.bak" ] && cp -a "$BK/persistent.sqlite.bak" /data/misc/keystore/persistent.sqlite 2>/dev/null
restorecon -R /data/system/locksettings.db /data/system_de/0/spblob /data/misc/keystore 2>/dev/null
echo "[ok] restored. Reboot -> System."
