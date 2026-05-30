# AnyKernel3 Config for Redmi K60 (socrates | SM8475)
# Integrates: SukiSU-Ultra + SUSFS + Scheduler Opts
# Based on: https://github.com/osm0sis/AnyKernel3
# =========================================================

# AnyKernel3 init
properties() { '\'';
kernel.string=SukiSU-Ultra Kernel for Redmi K60 (socrates) | SukiSU + SUSFS;
do.devicecheck=1;
do.modules=0;
do.systemless=1;
do.cleanup=1;
do.cleanuponabort=0;
device.name1=socrates;
device.name2=socrates_in;
device.name3=socrates_global;
device.name4=2211133C;
device.name5=2211133G;
supported.versions=13-14;
supported.patchlevels=;
'\''}

# Shell variables
block=/dev/block/bootdevice/by-name/boot;
is_slot_device=0;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

### AnyKernel methods (do not remove!)
# import patching functions/variables - see also the [[AnyKernel3]] installer
. tools/ak3-core.sh;

### Redmi K60 (socrates) specific install

## boot (standard method: replace Image in boot)
split_boot;

flash_generic dtbo.img;

# patch kernel Image into boot partition
flash_boot;
