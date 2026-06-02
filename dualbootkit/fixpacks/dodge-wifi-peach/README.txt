Drop OxygenOS peach board-data here (bring your own from OxygenOS /odm/etc/wifi/peach/):
  bdwlan.b0i  bdwlan.b0a/b0c/b0e  bdwlang.b0*  regdb.bin  ...
SELinux label must be: u:object_r:firmware_file:s0
01-coloros-wifi-peach.sh overlays this dir onto /vendor/firmware_mnt/image/peach.
(No proprietary blobs are committed to this repo.)
