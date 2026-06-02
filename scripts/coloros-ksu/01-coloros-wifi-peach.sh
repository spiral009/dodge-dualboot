#!/data/adb/ksu/bin/busybox sh
# Cross-region WiFi fix: ColorOS-PJZ(CN) ships peach bdwlan.e0X but CPH hardware
# needs bdwlan.b0i. Overlay the OxygenOS peach board-data over firmware_mnt.
# Headless: post-fs-data.d, not a visible module.
BB=/data/adb/ksu/bin/busybox
OV=/data/adb/coloros_peach_fw           # OxygenOS /odm/etc/wifi/peach/* (label firmware_file:s0)
SRC=/vendor/firmware_mnt/image/peach
[ -d "$OV" ] && $BB mount -o bind "$OV" "$SRC" && echo "peach bind ok" > /data/coloros_wifi.log
