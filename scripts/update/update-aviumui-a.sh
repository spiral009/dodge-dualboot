#!/sbin/sh
# =====================================================================
#  update-aviumui-a.sh  -  Update AviumUI on slot _a ONLY, on-device,
#  NO PC / NO fastboot, WITHOUT touching ColorOS (_b).
#  Run in OrangeFox (Terminal):  sh /sdcard/update-aviumui-a.sh
#  Put your fresh AviumUI build images in /sdcard/aviumui_update/ :
#     boot.img init_boot.img dtbo.img vendor_boot.img
#     vbmeta.img vbmeta_system.img vbmeta_vendor.img
#     system.img system_ext.img product.img vendor.img odm.img
#     [vendor_dlkm.img odm_dlkm.img system_dlkm.img]
#
#  WHY IT IS _b-SAFE: it writes ONLY *_a block partitions and updates ONLY
#  *_a LOGICAL partitions inside super via lptools. It NEVER writes the whole
#  super image, so every ColorOS (*_b) partition stays byte-for-byte intact.
#
#  *** TEST CAREFULLY: verify your recovery's lptools verbs (resize/map/unmap)
#  *** and that super has free space in the _a group before relying on this.
# =====================================================================
DIR=${1:-/sdcard/aviumui_update}
say(){ echo ">> $*"; }
[ "$(id -u)" = 0 ] || { echo "ERROR: run as root in recovery"; exit 1; }
command -v lptools >/dev/null 2>&1 || { echo "ERROR: lptools not in this recovery"; exit 1; }
[ -d "$DIR" ] || { echo "ERROR: $DIR not found"; exit 1; }

say "1/3  boot-class images -> slot _a ONLY"
for img in boot init_boot dtbo vendor_boot vbmeta vbmeta_system vbmeta_vendor; do
  [ -f "$DIR/$img.img" ] || continue
  blk=/dev/block/by-name/${img}_a
  [ -e "$blk" ] || { say "   (no $blk - skip)"; continue; }
  dd if="$DIR/$img.img" of="$blk" bs=4M conv=fsync && say "   flashed ${img}_a"
done

say "2/3  logical partitions -> slot _a ONLY (inside super, ColorOS _b untouched)"
for p in system system_ext product vendor odm vendor_dlkm odm_dlkm system_dlkm; do
  [ -f "$DIR/$p.img" ] || continue
  sz=$(stat -c %s "$DIR/$p.img")
  lptools unmap ${p}_a 2>/dev/null || true
  lptools resize ${p}_a "$sz"  || { echo "ERROR: resize ${p}_a failed (super full in _a group?)"; exit 1; }
  lptools map ${p}_a
  dd if="$DIR/$p.img" of=/dev/block/mapper/${p}_a bs=4M conv=fsync && say "   updated ${p}_a ($sz B)"
done

say "3/3  set active slot _a"
bootctl set-active-boot-slot 0 2>/dev/null || say "   (bootctl failed - set Slot A in OrangeFox -> Reboot)"
sync
say "DONE. Reboot -> System (Slot A). ColorOS (_b) was not touched."
