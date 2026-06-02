#!/sbin/sh
# =====================================================================
#  cos2b  -  install a SECONDARY OS (ColorOS) into the spare slot, in
#  ONE elegant pass, from recovery, safely.  (in the spirit of ro2rw)
#
#   * touches ONLY the target/secondary slot - your daily slot is sacred
#   * ARB-gated: refuses firmware that would raise anti-rollback (brick)
#   * parks the OS bulk in a loopback data image (tiny super footprint)
#   * DRY-RUN by default: prints the whole plan, changes NOTHING
#
#   sh cos2b.sh [profile.conf] [--commit] [--yes]
#       (no profile = built-in dodge/ColorOS defaults)
#       --commit  actually do it       --yes  skip the typed confirmation
#
#  You bring your own ColorOS images (see tools/get-coloros.sh). Nothing
#  proprietary ships here. EXPERIMENTAL beyond dodge - dry-run, read, test.
# =====================================================================
set -u

# ---------- built-in defaults (OnePlus 13 dodge + ColorOS) ----------
OS_NAME="ColorOS"
KIT_DIR="/sdcard/dualbootkit"
TARGET_SLOT=""                       # "" = auto (the slot you are NOT daily-driving)
SECONDARY_GROUP="oneplus_dynamic_partitions"   # slot suffix appended below
FW_DIR="$KIT_DIR/coloros/firmware";  FW_IMAGES="abl aop boot dtbo init_boot vendor_boot tz hyp keymaster modem dsp vbmeta vbmeta_system vbmeta_vendor"
SUPER_DIR="$KIT_DIR/coloros/super";  LOGICAL_PARTS="system:system.img system_ext:system_ext.img product:product.img vendor:vendor.img odm:odm.img"
DATA_IMG="/sdcard/coloros_data.img"; DATA_IMG_SIZE=$((64*1024*1024*1024))
OVERLAY_SRC="$KIT_DIR/coloros/my_stock"; OVERLAY_DEST="coloros_mystock"
HEADLESS_DIR="$KIT_DIR/../scripts/coloros-ksu"   # 00-coloros-restore.sh, 01-coloros-wifi-peach.sh
DEVICE_ARB=0                         # your daily firmware's ARB ceiling (dodge = 0)

# ---------- args / profile ----------
COMMIT=0; ASSUME_YES=0; PROF=""
for a in "$@"; do case "$a" in
  --commit) COMMIT=1;; --yes) ASSUME_YES=1;; *.conf) PROF="$a";; esac; done
[ -n "$PROF" ] && [ -f "$PROF" ] && . "$PROF"

# ---------- pretty + safety helpers ----------
BAR="======================================================================"
say(){ echo; echo "$BAR"; echo "  $*"; echo "$BAR"; }
step(){ echo; echo ">> $*"; }
ok(){ echo "   [OK] $*"; }
die(){ echo; echo "   [ABORT] $*"; cleanup; exit 1; }
run(){ if [ "$COMMIT" = 1 ]; then echo "   + $*"; eval "$@" || die "command failed: $*"; else echo "   DRY  $*"; fi; }
MNT=/mnt/cos2b_data
cleanup(){ umount "$MNT" 2>/dev/null; }

say "cos2b : install $OS_NAME into the spare slot  (commit=$COMMIT)"

# ---------- 0. PRECHECK ----------
step "0. preflight"
[ "$(id -u)" = 0 ] || die "not root - run inside recovery"
[ -e /sbin/recovery ] || [ -e /system/bin/recovery ] || echo "   [warn] doesn't look like recovery - be sure you are NOT in your daily OS"
for t in lptools lpdump dd; do command -v "$t" >/dev/null 2>&1 || die "missing tool '$t' in this recovery"; done
ACTIVE=$(getprop ro.boot.slot_suffix 2>/dev/null); ACTIVE=${ACTIVE:-_a}
if [ -z "$TARGET_SLOT" ]; then [ "$ACTIVE" = "_a" ] && TARGET_SLOT="_b" || TARGET_SLOT="_a"; fi
[ "$TARGET_SLOT" != "$ACTIVE" ] || die "target ($TARGET_SLOT) == active/daily slot. Refusing to overwrite your running OS."
GRP="${SECONDARY_GROUP}${TARGET_SLOT}"
ok "active/daily slot = $ACTIVE   ->  installing to TARGET = $TARGET_SLOT (group $GRP)"
ok "this run targets ONLY $TARGET_SLOT (guarded against the active slot) - keep a Slot-A backup regardless"
[ -d "$FW_DIR" ]   || die "firmware dir missing: $FW_DIR  (run tools/get-coloros.sh first)"
[ -d "$SUPER_DIR" ]|| die "super images dir missing: $SUPER_DIR"

# ---------- 0b. ARB GATE (the part that prevents a brick) ----------
step "0b. anti-rollback gate (firmware ARB must be <= device ceiling $DEVICE_ARB)"
ARBF="$FW_DIR/.arb_index"
if [ -f "$ARBF" ]; then
  FW_ARB=$(cat "$ARBF" 2>/dev/null)
  echo "   firmware ARB index = ${FW_ARB:-?}   device ceiling = $DEVICE_ARB"
  if [ -n "${FW_ARB:-}" ] && [ "$FW_ARB" -gt "$DEVICE_ARB" ] 2>/dev/null; then
    die "firmware ARB ($FW_ARB) > device ceiling ($DEVICE_ARB). Flashing it would raise the fuse and BRICK your daily slot. Use an older ColorOS (dodge: <=16.0.2.403)."
  fi
  ok "ARB-safe"
else
  echo "   [warn] no $ARBF stamp (get-coloros.sh writes it). CANNOT auto-verify ARB."
  [ "$COMMIT" = 1 ] && [ "$ASSUME_YES" = 0 ] && die "refusing to flash firmware with unverified ARB (re-run tools/get-coloros.sh, or pass --yes to override at your own risk)"
fi

# ---------- 1. PLAN ----------
say "PLAN (review carefully)"
echo " firmware -> ${TARGET_SLOT} blocks : $FW_IMAGES"
echo " carve into $GRP             : $(for e in $LOGICAL_PARTS; do printf '%s ' "${e%%:*}${TARGET_SLOT}"; done)"
echo " data image                  : $DATA_IMG ($((DATA_IMG_SIZE/1024/1024/1024)) GiB, loopback = ${OS_NAME} /data)"
echo " my_stock                    : $OVERLAY_SRC  ->  inside image:/$OVERLAY_DEST (label-preserving)"
echo " headless scripts            : $(ls "$HEADLESS_DIR" 2>/dev/null | tr '\n' ' ')"
echo; echo " current super groups:"; lpdump 2>/dev/null | grep -iE "group|free|name:" | sed 's/^/   /' | head -40

# ---------- CONFIRM ----------
if [ "$COMMIT" = 1 ] && [ "$ASSUME_YES" = 0 ]; then
  echo; printf "Type the target slot ('%s') to proceed, anything else aborts: " "$TARGET_SLOT"
  read ans; [ "$ans" = "$TARGET_SLOT" ] || die "not confirmed"
fi
[ "$COMMIT" = 1 ] || { say "DRY-RUN complete - nothing changed. Re-run with --commit when the plan looks right."; exit 0; }

# ---------- 2. FIRMWARE -> target slot only ----------
step "1. firmware/boot -> ${TARGET_SLOT} (daily slot untouched)"
for img in $FW_IMAGES; do
  src="$FW_DIR/$img.img"; blk="/dev/block/by-name/${img}${TARGET_SLOT}"
  [ -f "$src" ] || { echo "   skip $img (no image)"; continue; }
  [ -e "$blk" ] || { echo "   skip $img (no $blk)"; continue; }
  run "dd if='$src' of='$blk' bs=4M conv=fsync"; ok "${img}${TARGET_SLOT}"
done

# ---------- 3. carve logical partitions into target group ----------
step "2. carve ${OS_NAME} logical partitions into $GRP"
for e in $LOGICAL_PARTS; do
  name="${e%%:*}${TARGET_SLOT}"; img="$SUPER_DIR/${e##*:}"
  [ -f "$img" ] || { echo "   skip $name (no $img)"; continue; }
  sz=$(stat -c %s "$img")
  run "lptools remove $name 2>/dev/null || true"
  run "lptools create $name $sz $GRP"
  run "lptools map $name"
  run "dd if='$img' of=/dev/block/mapper/$name bs=4M conv=fsync"; ok "$name ($sz B)"
done

# ---------- 4. loopback data image + my_stock ----------
step "3. build loopback data image + extract my_stock inside it"
run "dd if=/dev/zero of='$DATA_IMG' bs=4096 count=0 seek=$((DATA_IMG_SIZE/4096))"
run "mkfs.f2fs -f '$DATA_IMG' >/dev/null 2>&1"
run "mkdir -p '$MNT'"; run "mount -o loop '$DATA_IMG' '$MNT'"
if [ -d "$OVERLAY_SRC" ]; then
  run "mkdir -p '$MNT/$OVERLAY_DEST'"
  run "cp -a '$OVERLAY_SRC/.' '$MNT/$OVERLAY_DEST/'"
  echo "   relabel (toybox cp -a drops SELinux ctx; re-apply from source):"
  run "(cd '$OVERLAY_SRC' && find . | while read f; do c=\$(ls -dZ \"\$f\" 2>/dev/null | awk '{print \$1}'); [ -n \"\$c\" ] && chcon -h \"\$c\" \"$MNT/$OVERLAY_DEST/\${f#./}\" 2>/dev/null; done)"
  ok "my_stock copied + relabeled"
fi
run "mkdir -p '$MNT/adb/post-fs-data.d'"
for s in "$HEADLESS_DIR"/*.sh; do
  [ -f "$s" ] || continue
  run "cp '$s' '$MNT/adb/post-fs-data.d/$(basename "$s")'"
  run "chmod 0755 '$MNT/adb/post-fs-data.d/$(basename "$s")'"; ok "headless: $(basename "$s")"
done
run "sync"; run "umount '$MNT'"

# ---------- DONE ----------
say "DONE - ${OS_NAME} installed to slot ${TARGET_SLOT}, daily slot ${ACTIVE} untouched"
echo "  Next: OrangeFox -> Reboot -> Slot ${TARGET_SLOT#_} -> System."
echo "  WiFi fix: drop OxygenOS peach board-data where 01-coloros-wifi-peach.sh expects it."
echo "  If a slot ever won't unlock after switching: sh /sdcard/aviumui_fix.sh (see repo)."
cleanup
