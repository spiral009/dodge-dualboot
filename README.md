# OnePlus 13 (dodge) True Dual-Boot: custom AOSP `_a` + ColorOS `_b`, with ColorOS in a loopback

Run a full custom AOSP ROM (**AviumUI**) on slot **`_a`** as your daily driver **and** keep stock **ColorOS** on slot **`_b`** for the things only stock does well (OnePlus Camera HAL, Tango/arm32) — on a single device, switchable from recovery, **with no PC needed for AviumUI updates** and **near-zero `super` cost for ColorOS**.

> This is a working setup on a OnePlus 13 **CPH2649 (dodge, SM8750)**. It documents a real build, including the traps that cost days. Adapt, don't blindly copy — flashing the wrong thing bricks slots.

---

## Why this is different from "just A/B two ROMs"

Naive A/B dual-boot puts two full systems in `super` and they fight over space, firmware, and security state. This setup avoids most of that:

- **ColorOS barely touches `super`.** ColorOS's bulky `my_stock` (~6.6 GB of preinstalled framework/overlays) and all of its userdata live **inside a single loopback file**, `coloros_data.img`, on shared userdata — *not* as `super` partitions. So `super_b` is tiny, leaving the rest of `super` free for AviumUI `_a` to **grow across updates**.
- **ColorOS bloat (`my_preload`) is dropped**; the one app worth keeping (Douyin/TikTok) comes back as a normal APK.
- **Zero data loss / DFE.** Force-encryption is disabled (`ro.crypto.state=unsupported`); `/data` is plaintext, so recovery and maintenance are trivial and a slot mistake never costs your files.
- **Cross-region WiFi fixed** without a kernel rebuild (PJZ/CN ColorOS on global CPH hardware needs `peach/bdwlan.b0i`).
- **Root mods are headless** — loaded by `ksud` from `post-fs-data.d`, invisible in the KSU manager.
- **AviumUI updates flash on-device from OrangeFox** — no laptop, no `fastboot` — and **without disturbing ColorOS `_b`**.

---

## Architecture

```
super (one physical partition)
├── _a group: AviumUI logical partitions (system_a, system_ext_a, product_a, vendor_a, odm_a, ...)
│            → full custom AOSP, free to grow (most of super is here)
└── _b group: ColorOS logical partitions — MINIMAL (system_b/vendor_b/product_b only)
             → NO my_stock partition, NO big userdata here

userdata (shared, DFE / plaintext)
└── /data/media/0/coloros_data.img   ← 64 GB f2fs loopback = ColorOS's ENTIRE /data
        ├── /coloros_mystock          ← ColorOS my_stock extracted here (bind-mounted at boot)
        └── /adb/post-fs-data.d/*.sh  ← headless ColorOS fixes (my_stock bind, WiFi)

firmware partitions (per-slot: *_a / *_b) → each OS gets its matching boot chain + modem/dsp/tz
TEE / Weaver / Gatekeeper / RPMB → SHARED hardware, NOT slotted (see "Shared-TEE gotcha")
```

Switch OS: **OrangeFox → Reboot → Slot A / Slot B → System.**

---

## Part 1 — Getting ColorOS into `_b` (the loopback trick)

High level (bring your **own** ColorOS images — they are not redistributed here):

1. **Firmware/boot chain to `_b`** — flash ColorOS `abl/boot/dsp/modem/tz/vendor_boot/...` to the `*_b` partitions (a "SuperHybrid"-style flasher zip that `dd`s `COS_FILES_HERE/*.img` to `<name>_b`). ARB-check first (`xbl_config` OEM ARB index must match; on dodge, `16.0.2.x` = ARB 0).
2. **Minimal ColorOS in `super_b`** — `lpmake` only `system_b/vendor_b/product_b`. Do **not** add `my_stock` as a partition.
3. **`coloros_data.img`** — create a 64 GB f2fs image on userdata; this becomes ColorOS's `/data`. ColorOS mounts it instead of the shared userdata (loop, pinned).
4. **Extract `my_stock` into the image** — mount the original `my_stock`, `cp -a` its contents to `coloros_data.img:/coloros_mystock`, **preserving SELinux labels** (toybox `cp -a` does **not** copy `security.selinux` — relabel from the mounted original with `find … -exec ls -dZ` → grouped `chcon -h`; the `-h` is essential for symlinks).
5. **Headless bind at boot** — `scripts/coloros-ksu/00-coloros-restore.sh` binds `/data/coloros_mystock` → `/mnt/vendor/my_stock` → `/my_stock`.
6. **WiFi** — drop OxygenOS `peach` board-data (incl. `bdwlan.b0i`) into `/data/adb/coloros_peach_fw` (label `firmware_file:s0`); `scripts/coloros-ksu/01-coloros-wifi-peach.sh` overlays it on `/vendor/firmware_mnt/image/peach`.
7. **Drop `my_preload`** bloat; reinstall any wanted app as a normal APK.

Gotchas that cost time:
- `ksud` runs `post-fs-data.d/*.sh` **headless** (no metamodule), but scripts **must** use `#!/data/adb/ksu/bin/busybox sh` — `/system/bin/sh` isn't in ksud's early namespace on ColorOS.
- **Loop-on-loop fails**: an EROFS image *inside* `coloros_data.img` can't be loop-mounted (I/O error). Bind an extracted **directory** instead of nesting loops.

---

### Make it reproducible: `dualbootkit/`

So *anyone* who runs one custom ROM on `_a` can fill the empty `_b` half of `super` with a secondary OS, see **[`dualbootkit/`](dualbootkit/)** — a config-driven, **dry-run-by-default** installer: it `lpdump`-detects your layout, carves the secondary OS's logical partitions into the free `_b` group via `lptools` (no whole-super rewrite), builds the `<os>_data.img` loopback, extracts the bulky `my_stock` into it (label-preserving), and drops the headless WiFi/bind scripts. You bring your own stock images (a PC extractor is included); a tested `dodge-coloros` profile and a blank `TEMPLATE.conf` are provided.

## Part 2 — Updating AviumUI `_a` with NO laptop / NO fastboot — and without touching ColorOS

**The trap:** a normal full-ROM zip flashes boot to *both* slots and writes the *whole* `super` (`simg2img super.img → /dev/block/by-name/super`). For a *clean install* that's fine; for an *update* it **destroys ColorOS `_b`**.

**The fix:** update **slot `_a` only**, at the logical-partition level, inside the live `super`:

- boot-class images → `*_a` blocks only
- `system_a/vendor_a/product_a/...` → updated via **`lptools`** inside `super` (every `*_b` partition stays byte-for-byte)
- `set-active-boot-slot _a` → reboot

This is `scripts/update/update-aviumui-a.sh`. Workflow with no PC:

```
# build machine:  repo sync && build → produces the per-partition .img files
# transfer to phone over network (croc / scp / your adb tunnel) into /sdcard/aviumui_update/
# phone: boot OrangeFox → Terminal:
sh /sdcard/update-aviumui-a.sh
# → Reboot → System (Slot A).  ColorOS _b untouched.
```

> It works *because* ColorOS lives in the loopback and barely uses `super` — there's headroom for `_a` to grow. Verify your recovery's `lptools` verbs and that the `_a` group has free space before relying on it. Test on the inactive slot first.

---

## Part 3 — The shared-TEE gotcha (read this before you set a lock screen)

`_a` and `_b` share the **hardware TEE / Gatekeeper / Weaver / keystore root** — it is **not** slotted and **not** inside `coloros_data.img`, so data-isolation can't wall it off. Setting up user-0 security on one OS can desync the other's `user 0` keystore binding. Symptom on the affected OS: boots to `FallbackHome`, `RUNNING_LOCKED`, no `/sdcard`, keymaster `IKMHal_sendCmd failed -28/-30`.

**Your data is never lost** when this happens (DFE → plaintext). Recover in ~1 minute:

```
# OrangeFox on the stuck slot:
adb shell sh /sdcard/aviumui_fix.sh    # backs up, then clears credential + keystore TOGETHER
# Reboot → System → boots PASSWORDLESS → set a new PIN in Settings.
```

**Critical trap:** clearing *only* the credential (`locksettings.db`+`spblob`) **bootloops** (lost `MIGRATED_SP_FULL` → `initKeystoreSuperKeys` fails). You must clear the credential **and** the keystore together — which `aviumui_fix.sh` does. `aviumui_restore.sh` undoes it.

Forensic note (in case you're tempted by the popular "fix"): on this build ColorOS `_b` uses a **gatekeeper+secdiscardable** protector, **not** a Weaver slot — so the widely-suggested `config_disableWeaverOnUnsecuredUsers` overlay is a **no-op here**. The real shared vector is the gatekeeper/keystore `user 0` binding, and whether it recurs every switch (vs a one-time first-setup event) is **not yet proven** — measure before you "fix."

---

## Scripts in this repo

| Path | Runs where | Does |
|---|---|---|
| `scripts/recovery/aviumui_fix.sh` | OrangeFox (root) | Back up + clear credential & keystore → AviumUI boots passwordless |
| `scripts/recovery/aviumui_restore.sh` | OrangeFox (root) | Undo the above (restore newest backup) |
| `scripts/update/update-aviumui-a.sh` | OrangeFox (root) | Update AviumUI `_a` only, on-device, ColorOS `_b` untouched |
| `scripts/coloros-ksu/00-coloros-restore.sh` | ColorOS `post-fs-data.d` | Bind extracted `my_stock` from inside `coloros_data.img` |
| `scripts/coloros-ksu/01-coloros-wifi-peach.sh` | ColorOS `post-fs-data.d` | Cross-region WiFi: overlay OxygenOS `peach` board-data |

## Status & honesty

Working: dual-boot, ColorOS in loopback (~tiny super), DFE/zero-data-loss, WiFi, calls/SIM1, headless root, on-device `_a` update path, 1-minute lock recovery.
Unsolved/known: **SIM 2** on ColorOS (modem won't probe the 2nd physical slot under CN ColorOS — modem-NV level, no safe software fix found). Shared-TEE recurrence not fully characterized.

No ColorOS/OnePlus proprietary images are included — bring your own. Not affiliated with OnePlus/OPPO. You flash at your own risk.
