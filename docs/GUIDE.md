# OnePlus 13 (dodge) Dual-Boot — Complete Manual (build, drop, restore)

> **Audience:** future-me, or any AI/operator with root + OrangeFox recovery + this repo, who must
> rebuild, remove, or restore the ColorOS-in-`_b` setup **alone**, from a known state, without guessing.
> This document is intentionally plain and exhaustive. Read every ⚠️.

---

## 0. READ FIRST (safety, scope, ultimate recovery)

- This modifies firmware and the `super` partition. **Mistakes can hard-brick a slot or the whole device.**
- **Golden rule:** all operations target the **secondary slot only** (the one you do NOT daily-drive). Never write a `*_a` partition while AviumUI lives on `_a`. The scripts enforce this; if you go manual, *you* enforce it.
- **Anti-rollback (ARB) is the brick risk.** ARB is a **single device-wide fuse, not per-slot** — anything you ever flash to `_b` raises it for `_a` too. Flashing ColorOS firmware whose ARB index is *higher* than your current fuse raises it irreversibly and will **brick your daily OS** (it can no longer boot). Our dodge baseline = **0** (measured via `arbscan`, not assumed). See §A1 and Appendix A.
- **Your data is plaintext (DFE).** `ro.crypto.state=unsupported`; `/data` and `/sdcard` are not encrypted. This is why recovery edits work and why a slot mistake never costs files — but it is also *less* secure; that is an accepted trade-off here.
- **Ultimate recovery (un-brick):** OnePlus 13 supports **MSM Download Tool / EDL (9008)**. A full MSM restore returns the device to 100% stock (both slots, all firmware) and **erases everything**. Keep the MSM package + a working USB-C cable + a Windows machine (or a VM) available. This is the floor under every step below.
- Nothing proprietary (ColorOS images/firmware) is included in this repo. You supply your own from official sources.

### What is safe vs dangerous
| Action | Risk |
|---|---|
| `lpdump`, mounting images **read-only**, reading partitions | safe |
| Editing files in `coloros_data.img` (the loopback) | safe (it's just ColorOS's `/data`) |
| `dd` to `*_b` blocks / `lptools` on `*_b` while on `_a` | medium — wrong image bricks `_b` only, `_a` survives |
| `dd` to `*_a` / writing whole `super` / wrong ARB firmware | **HIGH — can brick your daily OS / device** |

### 0b. STATUS — proven on dodge vs not (read before trusting this)
**PROVEN (actually running on the device):**
- ColorOS `_b` **boots and runs** with `/data` = the `coloros_data.img` loopback; `my_stock` bind-mounts; WiFi (peach) works; SIM 1/calls work. The loopback-`/data` design is **not** theoretical here — it's the live setup.
- DFE/plaintext `/data`; the shared-TEE lock recovery (`aviumui_fix.sh`) — used successfully.
- ARB indices **measured with `arbscan`**: device + OOS.402 + COS.403 = index **0**; COS.703 = **1** (advances at 16.0.3.50x). Verified, not assumed.

**NOT YET PROVEN (experimental):**
- `cos2b.sh` / §A3 doing the `super` carve **on-device with `lptools`**. The original `_b` install used a **super-rebuild** route, not an on-device carve. On a **Virtual A/B** device the inactive `_b` group is often COW/zero-sized, so `lptools create … _b` may have no space → fall back to a PC `lpmake` super rebuild. **Dry-run + `lpdump` first.**
- Exact `lptools` verb set varies by OrangeFox build.

**REAL ESCAPE HATCH:** a full **MSM/EDL stock restore** (or fastboot flashall of full stock firmware for your *exact* model), prepared on a PC **before** you start. The PART B partition-removal steps are convenience, **not** your safety net.

---

## 1. Glossary (so nothing is ambiguous)

- **Slot `_a` / `_b`:** the two A/B copies of every firmware/system partition. Here: **`_a` = AviumUI (daily, custom AOSP)**, **`_b` = ColorOS (stock, secondary)**.
- **`super`:** one physical partition holding *logical/dynamic* partitions (`system_a`, `vendor_b`, …) grouped per slot (`oneplus_dynamic_partitions_a` / `_b`).
- **Logical/dynamic partition:** a resizable partition living inside `super`, managed by `lpmake`/`lpdump`/`lptools`.
- **DFE:** Disable Force Encryption — `/data` is plaintext (no FBE). Confirm: `getprop ro.crypto.state` → `unsupported`.
- **FBE:** File-Based Encryption (what DFE turns off).
- **ARB:** Anti-RollBack — a hardware fuse storing the minimum allowed firmware version. Flashing higher-ARB firmware raises it irreversibly.
- **Weaver / Gatekeeper / Keystore:** the lock-screen/credential hardware in the TEE. **Shared by both slots**, not slotted — the source of the "stuck locked" gotcha (§D1).
- **Loopback data image (`coloros_data.img`):** a 64 GiB f2fs file at `/data/media/0/coloros_data.img` that *is* ColorOS's entire `/data`. Keeps ColorOS out of `super`.
- **`my_stock`:** ColorOS's bulky preinstalled framework/overlay partition (~6.6 GB). Here it is **extracted into** the loopback at `/coloros_mystock` and bind-mounted, **not** a `super` partition.
- **`my_preload`:** ColorOS bloatware partition — **dropped** in this setup.
- **OFOX:** OrangeFox recovery.

---

## 2. The setup at a glance

```
SLOT _a  = AviumUI (custom AOSP)  — daily driver, has the lock screen
SLOT _b  = ColorOS (stock)        — secondary, passwordless

super:
  oneplus_dynamic_partitions_a : full AviumUI logical partitions (free to grow)
  oneplus_dynamic_partitions_b : MINIMAL ColorOS (system_b, system_ext_b, product_b, vendor_b, odm_b)
                                 NO my_stock, NO big data here

userdata (shared, DFE/plaintext):
  /data/media/0/coloros_data.img        = ColorOS's ENTIRE /data (64 GiB f2fs loopback)
      ├── /coloros_mystock              = ColorOS my_stock contents (bind-mounted at boot)
      └── /adb/post-fs-data.d/*.sh      = headless fixes (my_stock bind, WiFi)

firmware (per slot, *_a / *_b): each OS keeps its own boot chain + modem/dsp/tz/etc.
TEE (Weaver/Gatekeeper/Keystore/RPMB): SHARED hardware — NOT slotted (see §D1)
```
Switch OS: **OFOX → Reboot → Slot A / Slot B → System.**

---

## 3. Prerequisites

1. Bootloader unlocked; **OrangeFox** installed and bootable on both slots.
2. **Root (KernelSU)** working on `_a` (and on `_b` once installed).
3. This repo's `dualbootkit/` + `scripts/` copied to the phone at `/sdcard/dualbootkit/` and `/sdcard/` (the recovery scripts).
4. **Your own ColorOS** full OTA for dodge (official OPPO/OnePlus source). **Version ≤ 16.0.2.403** (ARB 0). See §A1.
5. **OxygenOS `peach` WiFi board-data** (incl. `bdwlan.b0i`) from an OxygenOS `/odm/etc/wifi/peach/` for dodge (for §A3 step 6).
6. A PC with `payload-dumper-go`, `python3`, and (if your OTA is `.ozip`) `ozipdecrypt`.
7. ⚠️ **MSM/EDL package ready** as the un-brick floor.

---

## 4. Backups you MUST make first (in OrangeFox, root)

```sh
mkdir -p /sdcard/dualboot_backups
# boot chain of BOTH slots (small, lets you restore a slot that won't boot)
for s in _a _b; do for p in boot init_boot dtbo vendor_boot vbmeta vbmeta_system vbmeta_vendor; do
  dd if=/dev/block/by-name/${p}${s} of=/sdcard/dualboot_backups/${p}${s}.img 2>/dev/null; done; done
# super metadata + a full lpdump (so you can recreate the partition layout)
lpdump > /sdcard/dualboot_backups/lpdump.txt 2>&1
# the existing ColorOS data image (if present) — large; copy to PC if space is short
ls -la /data/media/0/coloros_data.img
# the lock-screen backups created by aviumui_fix.sh live in /sdcard/aviumui_lock_backup_* / lock_backup_*
```
⚠️ A **full `super` image** backup (`dd if=/dev/block/by-name/super`) is ~8 GB — do it to PC if you have room; it is the cleanest "undo".

---

## PART A — Install ColorOS into `_b` from scratch

### A1. Obtain ColorOS images + verify ARB (PC side)
```sh
# from this repo on a PC:
dualbootkit/tools/get-coloros.sh  <official-OTA.zip|payload.bin|.ozip|URL>  ./coloros_out  --device-arb 0
```
- This extracts into `coloros_out/firmware/` + `coloros_out/super/`, **reads the firmware ARB index** with `tools/arbscan.py`, and **REFUSES** anything with ARB > 0 (would raise the fuse and brick `_a`). It stamps `firmware/.arb_index`.
- ⚠️ If it refuses: your OTA is too new (≥ 16.0.3.50x). Get an **older** build (≤ 16.0.2.403). Do **not** override unless you understand you may brick `_a`.
- To learn your device's *real* current ceiling: in OFOX, `dd if=/dev/block/by-name/xbl_config_a of=/sdcard/xblcfg_a.img`, copy to PC, `python3 dualbootkit/tools/arbscan.py /sdcard/xblcfg_a.img`. Pass that number as `--device-arb`.
- Also extract **`my_stock`**: mount the OTA's `my_stock` (or its image) and copy its **contents** to `coloros_out/my_stock/`.
- Copy `coloros_out/*` to the phone at `/sdcard/dualbootkit/coloros/` (so you have `coloros/firmware`, `coloros/super`, `coloros/my_stock`).

### A2. The one-shot (recommended) — `cos2b.sh`
In **OrangeFox → Terminal**, booted on `_a` (so target auto-resolves to `_b`):
```sh
sh /sdcard/dualbootkit/cos2b.sh                 # DRY-RUN: prints the full plan, changes NOTHING
# read the plan. If correct:
sh /sdcard/dualbootkit/cos2b.sh --commit        # type the slot when prompted to confirm
# then: OFOX → Reboot → Slot B → System.
```
`cos2b.sh` refuses if target == active slot, enforces the ARB stamp, carves `_b`, builds the loopback, extracts `my_stock` (label-preserving), and installs the headless scripts — all in one pass. **If you trust it, you can stop here.** §A3 is the same thing done by hand.

### A3. Manual equivalent (if you don't use the script, or to understand it)
All in OrangeFox, root, **booted on `_a`** (target = `_b`). `D=/sdcard/dualbootkit/coloros`.
1. **ARB gate (do not skip):** confirm `cat $D/firmware/.arb_index` is `0` (or ≤ your `xbl_config_a` ARB). If higher, **STOP**.
2. **Firmware/boot → `_b` only:**
   ```sh
   for img in abl aop boot dtbo init_boot vendor_boot tz hyp keymaster modem dsp vbmeta vbmeta_system vbmeta_vendor; do
     [ -f "$D/firmware/$img.img" ] && [ -e /dev/block/by-name/${img}_b ] &&
       dd if="$D/firmware/$img.img" of=/dev/block/by-name/${img}_b bs=4M conv=fsync; done
   ```
   ⚠️ Note the `_b` suffix on every target. Never `_a`.
3. **Carve ColorOS logical partitions into the `_b` group:**
   ```sh
   for e in system:system.img system_ext:system_ext.img product:product.img vendor:vendor.img odm:odm.img; do
     n=${e%%:*}_b; img="$D/super/${e##*:}"; [ -f "$img" ] || continue; sz=$(stat -c %s "$img")
     lptools remove $n 2>/dev/null
     lptools create $n $sz oneplus_dynamic_partitions_b
     lptools map $n
     dd if="$img" of=/dev/block/mapper/$n bs=4M conv=fsync
   done
   ```
   ⚠️ If `lptools create` says *no space*: the `_b` group is collapsed — you must resize the group / rebuild `super` with `lpmake` (advanced; back up `super` first).
4. **Create the loopback data image (= ColorOS `/data`):**
   ```sh
   dd if=/dev/zero of=/data/media/0/coloros_data.img bs=4096 count=0 seek=$((64*1024*1024*1024/4096))
   mkfs.f2fs -f /data/media/0/coloros_data.img
   mkdir -p /mnt/cosd; mount -o loop /data/media/0/coloros_data.img /mnt/cosd
   ```
5. **Extract `my_stock` INTO the image, preserving SELinux labels** (⚠️ the trap that broke the UI the first time — `toybox cp -a` does NOT copy `security.selinux`):
   ```sh
   mkdir -p /mnt/cosd/coloros_mystock
   cp -a "$D/my_stock/." /mnt/cosd/coloros_mystock/
   # re-apply contexts from the source tree:
   (cd "$D/my_stock" && find . | while read f; do
       c=$(ls -dZ "$f" 2>/dev/null | awk '{print $1}'); [ -n "$c" ] && chcon -h "$c" "/mnt/cosd/coloros_mystock/${f#./}" 2>/dev/null; done)
   ```
   ⚠️ `chcon -h` (the `-h`) is essential or symlinks get mislabeled.
6. **Headless boot scripts** (invisible — not KSU modules):
   ```sh
   mkdir -p /mnt/cosd/adb/post-fs-data.d
   cp /sdcard/dualbootkit/../scripts/coloros-ksu/00-coloros-restore.sh /mnt/cosd/adb/post-fs-data.d/
   cp /sdcard/dualbootkit/../scripts/coloros-ksu/01-coloros-wifi-peach.sh /mnt/cosd/adb/post-fs-data.d/
   chmod 0755 /mnt/cosd/adb/post-fs-data.d/*.sh
   # WiFi board-data the 01 script overlays (label firmware_file:s0):
   mkdir -p /mnt/cosd/adb/coloros_peach_fw
   cp -a /path/to/oxygenos/peach/. /mnt/cosd/adb/coloros_peach_fw/
   chcon -R u:object_r:firmware_file:s0 /mnt/cosd/adb/coloros_peach_fw 2>/dev/null
   sync; umount /mnt/cosd
   ```
   ⚠️ `post-fs-data.d` scripts MUST start with `#!/data/adb/ksu/bin/busybox sh` — `/system/bin/sh` is not in ksud's early namespace on ColorOS.

### A4. First boot of `_b` + verify
- OFOX → Reboot → **Slot B** → System. First boot is slow (ColorOS first-run).
- Verify (adb/terminal on `_b`):
  - `getprop ro.boot.slot_suffix` → `_b`
  - `mount | grep my_stock` → bound
  - `cat /data/coloros_restore.log` → `my_stock bound OK`
  - WiFi works (peach overlay); `cat /data/coloros_wifi.log` → `peach bind ok`
- ⚠️ Known limit: **SIM 2 will not work on ColorOS** (modem won't probe the 2nd physical slot under CN ColorOS; modem-NV level, no safe fix found). SIM 1 + calls work. Both SIMs work on AviumUI `_a`.

---

## PART B — Drop ColorOS (reclaim the space)

Goal: remove ColorOS from `_b`, free `super` + the 64 GB image, **without touching `_a`**.
Do this **booted on `_a`** or in OrangeFox (NOT booted on `_b`).

> ⚠️ The reliable full reset is an **MSM/EDL stock restore** — the steps below are the *surgical* reclaim, a convenience, **not** your safety net.
> ⚠️ Do **NOT** `dd /dev/zero` over `boot_b` / `vendor_boot_b` as "cleanup" (a popular but dangerous suggestion): one wrong `by-name` path kills your daily slot and it buys you nothing. Leaving stale `_b` boot images is harmless if you don't boot `_b`.

1. **Remove the `_b` logical partitions** (frees `super` space):
   ```sh
   for n in system_b system_ext_b product_b vendor_b odm_b; do lptools remove "$n" 2>/dev/null; done
   ```
2. **Delete the loopback data image** (frees 64 GB on userdata):
   ```sh
   rm -f /data/media/0/coloros_data.img
   ```
3. **Firmware on `_b`:** you may leave the ColorOS firmware on `*_b` (harmless if you won't boot `_b`), OR mirror `_a`'s firmware onto `_b` so A/B **seamless OTA updates of AviumUI work again**:
   ```sh
   for p in boot init_boot dtbo vendor_boot vbmeta vbmeta_system vbmeta_vendor; do
     dd if=/dev/block/by-name/${p}_a of=/dev/block/by-name/${p}_b bs=4M conv=fsync; done
   # (and re-mirror the _a logical partitions into the _b group if you want true seamless OTA)
   ```
   ⚠️ Only mirror `_a → _b`. Never the reverse.
4. **Set active slot back to `_a`** and reboot: `bootctl set-active-boot-slot 0` (or OFOX → Slot A).
5. **Verify** reclaimed space: `lpdump` (no `*_b` ColorOS partitions), `df /data` (64 GB back).

⚠️ Dropping ColorOS does **not** undo the shared-TEE state. If you had switched between OSes, see §D1; your `_a` lock may still need the one-time `aviumui_fix.sh`.

---

## PART C — Get ColorOS back later

Everything you need is reproducible: **re-run PART A.** Keep these so it's painless:
- Your ARB-safe ColorOS OTA (or the extracted `coloros_out/`),
- The OxygenOS `peach` board-data,
- This repo (`dualbootkit/` + `scripts/`).
If you kept the old `coloros_data.img` (copied to PC), you can skip re-extracting `my_stock`: just restore the image to `/data/media/0/coloros_data.img` and do PART A steps 2–3 (firmware + carve) only.

---

## PART D — Troubleshooting

### D1. After switching slots, the other OS is stuck "locked" / no launcher / bootloop
**Cause:** `_a` and `_b` share the TEE Gatekeeper/Weaver/keystore for `user 0`; setting up security on one desyncs the other's keystore binding. Symptom: `FallbackHome`, `RUNNING_LOCKED`, no `/sdcard`, keymaster `IKMHal_sendCmd failed -28/-30`.
**Your data is safe** (DFE/plaintext). **Fix (in OrangeFox on the stuck slot):**
```sh
sh /sdcard/aviumui_fix.sh      # backs up, then clears credential + keystore TOGETHER
# Reboot → System → boots PASSWORDLESS → set a new PIN in Settings.
```
⚠️ **Do NOT** delete only `locksettings.db`/`spblob` — that bootloops (lost `MIGRATED_SP_FULL` → `initKeystoreSuperKeys` fails). The fix clears credential **and** keystore together. Undo: `sh /sdcard/aviumui_restore.sh`.
Note: on this build ColorOS `_b` uses gatekeeper+secdiscardable (not a Weaver slot), so the popular `config_disableWeaverOnUnsecuredUsers` overlay is a **no-op** here.

### D2. ColorOS WiFi missing
The `peach` board-data overlay didn't apply. Check `cat /data/coloros_wifi.log`, that `/data/adb/coloros_peach_fw` has `bdwlan.b0i` with label `firmware_file:s0`, and that `01-coloros-wifi-peach.sh` ran.

### D3. `_b` won't boot at all
Likely wrong/incomplete firmware or super carve, or ARB mismatch. Restore `_b` boot from `/sdcard/dualboot_backups`, re-check §A1 ARB, re-do §A3 steps 2–3. `_a` is unaffected.

### D4. Updating AviumUI `_a` without a PC (and without killing `_b`)
Use `scripts/update/update-aviumui-a.sh` — it flashes `_a` boot blocks + `lptools`-updates only `*_a` logical partitions inside `super`. ⚠️ Never flash a whole `super.img` for an update — that wipes `_b`.

### D5. Total brick / nothing boots
Use **MSM/EDL** to restore full stock, then start over. This is why §0 says keep MSM ready.

---

## Appendix A — ARB facts (dodge)
- ColorOS/OxygenOS **≤ 16.0.2.403 = ARB index 0** (safe baseline). OOS 16.0.2.402 and the device's shipped firmware are also ARB 0.
- ARB **advances at 16.0.3.50x** — flashing those raises the fuse; afterwards lower-ARB firmware (incl. AviumUI's boot chain) may refuse to boot → brick.
- Verify any image with `python3 dualbootkit/tools/arbscan.py <xbl_or_firmware.img>`.

## Appendix B — dodge logical partitions (typical)
`_a` and `_b` groups (`oneplus_dynamic_partitions_{a,b}`) each may contain: `system, system_ext, product, vendor, odm, vendor_dlkm, odm_dlkm, system_dlkm`. Confirm yours with `lpdump`. ColorOS `_b` here uses the minimal set: `system_b, system_ext_b, product_b, vendor_b, odm_b`.

## Appendix C — Files / scripts in this repo
- `dualbootkit/cos2b.sh` — one-shot ColorOS→`_b` installer (secondary-slot-only, ARB-gated, dry-run default)
- `dualbootkit/dualbootkit.sh` — lower-level profile-driven installer
- `dualbootkit/profiles/dodge-coloros.conf` / `TEMPLATE.conf` — device profiles
- `dualbootkit/tools/get-coloros.sh` — fetch official OTA + ARB-gate + lay out images
- `dualbootkit/tools/arbscan.py` — read OEM ARB index from xbl/xbl_config
- `dualbootkit/tools/extract-stock-images.sh` — generic OTA → images
- `scripts/recovery/aviumui_fix.sh` / `aviumui_restore.sh` — shared-TEE lock recovery
- `scripts/update/update-aviumui-a.sh` — update AviumUI `_a` on-device, `_b`-safe
- `scripts/coloros-ksu/00-coloros-restore.sh` / `01-coloros-wifi-peach.sh` — headless ColorOS fixes

## Appendix D — Honesty / status
Tested basis: OnePlus 13 (dodge) + ColorOS 16.0.2.403 + AviumUI. The `lptools` carve in `cos2b.sh`/§A3 is logically correct but **not yet verified end-to-end on-device** (verb names vary by OrangeFox build; group must have free space). Dry-run first, verify with `lpdump`, test on the inactive slot. No proprietary images are distributed. Not affiliated with OnePlus/OPPO. Flash at your own risk.
