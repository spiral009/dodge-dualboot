#!/sbin/sh
# =====================================================================
#  DualBootKit - install a SECONDARY OS into the spare _b half of an
#  A/B "super", with its bulk in a loopback data image so it costs
#  almost no super space. Run in OrangeFox/recovery as root.
#
#  DRY-RUN BY DEFAULT - prints the exact plan and changes NOTHING.
#  Add --commit to actually flash. Read the plan first. This can BRICK
#  a slot if your profile/images are wrong. You bring your own stock
#  images + firmware (nothing proprietary ships here).
#
#  Usage:  sh dualbootkit.sh profiles/<device-os>.conf [--commit]
# =====================================================================
set -u
CONF="${1:-}"; [ -n "$CONF" ] || { echo "usage: dualbootkit.sh <profile.conf> [--commit]"; exit 1; }
[ -f "$CONF" ] || { echo "profile not found: $CONF"; exit 1; }
COMMIT=0; [ "${2:-}" = "--commit" ] && COMMIT=1
. "$CONF"

DO(){ if [ "$COMMIT" = 1 ]; then echo "  + $*"; eval "$@"; else echo "  DRY  $*"; fi; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "FATAL: missing tool '$1' in this recovery"; exit 1; }; }
[ "$(id -u)" = 0 ] || { echo "FATAL: run as root (recovery)"; exit 1; }
need lptools; need lpdump; need dd
S="$SECONDARY_SLOT"

echo "================================================================"
echo " DualBootKit : install '$OS_NAME' into slot '$S'   commit=$COMMIT"
echo "================================================================"

echo; echo "## 1. current super layout (review before --commit)"
lpdump 2>/dev/null | sed -n '1,80p'

echo; echo "## 2. firmware / boot-chain -> ${S} blocks (bring-your-own in $FW_DIR)"
for img in $FW_IMAGES; do
  src="$FW_DIR/$img.img"; blk="/dev/block/by-name/${img}${S}"
  [ -f "$src" ] || { echo "  skip $img  (no $src)"; continue; }
  [ -e "$blk" ] || { echo "  skip $img  (no block $blk)"; continue; }
  DO "dd if='$src' of='$blk' bs=4M conv=fsync"
done
echo "  NOTE: ARB/anti-rollback is on YOU - flashing older-than-fused firmware bricks. Verify first."

echo; echo "## 3. carve secondary logical partitions into super (group: $SECONDARY_GROUP)"
for entry in $LOGICAL_PARTS; do            # entry = lname:imgfile
  name="${entry%%:*}"; img="$SUPER_DIR/${entry##*:}"
  [ -f "$img" ] || { echo "  skip $name  (no $img)"; continue; }
  sz=$(stat -c %s "$img")
  echo "  -- ${name}${S}  <= ${entry##*:} ($sz bytes)"
  DO "lptools remove ${name}${S} 2>/dev/null || true"
  DO "lptools create ${name}${S} $sz $SECONDARY_GROUP"
  DO "lptools map ${name}${S}"
  DO "dd if='$img' of=/dev/block/mapper/${name}${S} bs=4M conv=fsync"
done
echo "  If 'create' fails with no space: your _b group is collapsed; you must"
echo "  resize the group / rebuild super with lpmake (see dualbootkit/README.md)."

echo; echo "## 4. loopback data image ($DATA_IMG_SIZE) at $DATA_IMG  (keeps super tiny)"
DO "dd if=/dev/zero of='$DATA_IMG' bs=4096 count=0 seek=$(($DATA_IMG_SIZE/4096))"
DO "mkfs.f2fs -f '$DATA_IMG' >/dev/null 2>&1"
DO "mkdir -p /mnt/dbk_data"
DO "mount -o loop '$DATA_IMG' /mnt/dbk_data"

if [ -n "${OVERLAY_SRC:-}" ]; then
  echo; echo "## 4b. extract overlay '$OVERLAY_NAME' INTO the data image (label-preserving)"
  DO "mkdir -p /mnt/dbk_data/${OVERLAY_DEST}"
  DO "cp -a '${OVERLAY_SRC}/.' /mnt/dbk_data/${OVERLAY_DEST}/"
  echo "  RELABEL: toybox cp -a drops security.selinux. Re-apply from the source:"
  DO "(cd '$OVERLAY_SRC' && find . -exec sh -c 'ctx=\$(ls -dZ \"\$0\" 2>/dev/null | awk \"{print \\\$1}\"); [ -n \"\$ctx\" ] && chcon -h \"\$ctx\" \"/mnt/dbk_data/${OVERLAY_DEST}/\${0#./}\" 2>/dev/null' {} \;)"
fi

echo; echo "## 5. headless boot scripts into the data image (post-fs-data.d, invisible)"
DO "mkdir -p /mnt/dbk_data/adb/post-fs-data.d"
for s in $HEADLESS_SCRIPTS; do
  [ -f "$KIT_DIR/$s" ] || { echo "  skip $s (missing)"; continue; }
  DO "cp '$KIT_DIR/$s' /mnt/dbk_data/adb/post-fs-data.d/$(basename "$s")"
  DO "chmod 0755 /mnt/dbk_data/adb/post-fs-data.d/$(basename "$s")"
done
for fp in ${FIXPACKS:-}; do
  [ -d "$KIT_DIR/$fp" ] || continue
  echo "  fixpack: $fp -> ${FIXPACK_DEST:-/mnt/dbk_data/adb/}$(basename "$fp")"
  DO "mkdir -p /mnt/dbk_data/${FIXPACK_DEST:-adb}/$(basename "$fp")"
  DO "cp -a '$KIT_DIR/$fp/.' /mnt/dbk_data/${FIXPACK_DEST:-adb}/$(basename "$fp")/"
done

DO "sync"; DO "umount /mnt/dbk_data"
echo
echo "================================================================"
[ "$COMMIT" = 1 ] && echo " DONE. Set Slot $S in OrangeFox -> Reboot -> System." \
                   || echo " DRY-RUN complete. Review above, then re-run with --commit."
echo "================================================================"
