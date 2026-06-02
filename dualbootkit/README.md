# DualBootKit — turn the spare `_b` half of `super` into a real second OS

A single-ROM A/B device reserves a whole `_b` partition group in `super` that just sits empty. DualBootKit fills it with a **secondary OS** (e.g. stock ColorOS for camera/Tango), keeping that OS's bulk + userdata in a **loopback data image** so it costs almost no `super` space — and installs it **on-device from recovery, no PC, no fastboot**.

> **EXPERIMENTAL & device-specific.** The *method* is portable; the *details* (partition names, firmware, ColorOS images, fixes) are per-device and **you supply them**. The installer is **dry-run by default** — it prints the plan and changes nothing until you add `--commit`. Wrong images/firmware can brick a slot. Tested basis: OnePlus 13 (dodge) + ColorOS.

## How it works
1. `lpdump` the live `super` to see your slot/group layout.
2. `dd` the secondary OS's **firmware/boot** to `*_b` blocks only (your daily ROM on `_a` is never touched).
3. `lptools create` the secondary OS's **logical partitions** inside the free `_b` group (not a whole-super rewrite).
4. Create `<os>_data.img` (loopback f2fs) = the secondary OS's **entire `/data`**; extract its bulky preinstalled partition (`my_stock`) **into** that image, label-preserving.
5. Install **headless** `post-fs-data.d` scripts (my_stock bind, WiFi fix) — invisible in the root manager.

## Use it
On a PC (bring your own stock OTA — nothing proprietary ships here):
```bash
dualbootkit/tools/extract-stock-images.sh  coloros_payload.bin  ./coloros_out
# → coloros_out/firmware/* and coloros_out/super/*
```
Copy the kit + your images to the phone, then in **OrangeFox → Terminal**:
```sh
# 1) review the plan (changes NOTHING):
sh /sdcard/dualbootkit/dualbootkit.sh /sdcard/dualbootkit/profiles/dodge-coloros.conf
# 2) if the plan looks right, commit:
sh /sdcard/dualbootkit/dualbootkit.sh /sdcard/dualbootkit/profiles/dodge-coloros.conf --commit
# 3) Reboot → System → Slot B.
```

## Porting to another device
Copy `profiles/TEMPLATE.conf`, fill it from your `lpdump` output (group name, partition list, sizes), supply your firmware + super images + any fix-packs. Most OnePlus/OPPO VAB devices have a usable `_b` group; if `lptools create` reports no space, your `_b` group is collapsed and you must resize it / rebuild `super` with `lpmake` first (whole-super reflash — back up first).

## Hard limits (be honest with yourself)
- **No proprietary images included** — bring your own ColorOS/stock.
- **ARB / anti-rollback is on you** — verify firmware version before flashing `*_b`.
- **Shared TEE** — both OSes share Gatekeeper/Weaver/keystore; setting a lock on one can desync the other's `user 0`. See the repo root README + `scripts/recovery/aviumui_fix.sh`.
- Cross-device beyond dodge is **untested** — dry-run, read, and test on the inactive slot.
