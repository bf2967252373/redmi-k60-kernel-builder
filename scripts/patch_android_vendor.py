#!/usr/bin/env python3
"""
patch_android_vendor.py

Patches include/linux/android_vendor.h to unconditionally enable
ANDROID_VENDOR_DATA / ANDROID_OEM_DATA macros.

In socrates-t-oss, CONFIG_ANDROID_VENDOR_OEM_DATA has no Kconfig entry,
so make olddefconfig silently drops it. Without it, ANDROID_VENDOR_DATA(n)
expands to nothing, task_struct lacks android_vendor_data1, and
include/linux/sched/walt.h fails to compile.

Fix: strip the #ifdef CONFIG_ANDROID_VENDOR_OEM_DATA guard so the
"active" macro branch is always compiled.
"""
import re
import sys
from pathlib import Path

HEADER = Path("include/linux/android_vendor.h")

if not HEADER.exists():
    print(f"  {HEADER} not found, skipping.")
    sys.exit(0)

content = HEADER.read_text()
original = content

# ----------------------------------------------------------------
# Remove the opening guard line:
#   #ifdef CONFIG_ANDROID_VENDOR_OEM_DATA
# ----------------------------------------------------------------
content = re.sub(
    r'^#ifdef\s+CONFIG_ANDROID_VENDOR_OEM_DATA[ \t]*\n',
    '',
    content,
    flags=re.MULTILINE,
)

# ----------------------------------------------------------------
# Remove the #else...#endif block that contains empty stub macros.
# Pattern: '#else' followed by lines of empty #define ... up to '#endif'
# We match the specific empty-stub block structure.
# ----------------------------------------------------------------
content = re.sub(
    r'#else[ \t]*\n'
    r'(?:#define\s+ANDROID_VENDOR_DATA\([^)]*\)[ \t]*\n)'
    r'(?:#define\s+ANDROID_VENDOR_DATA_ARRAY\([^)]*\)[ \t]*\n)'
    r'(?:#define\s+ANDROID_OEM_DATA\([^)]*\)[ \t]*\n)'
    r'(?:#define\s+ANDROID_OEM_DATA_ARRAY\([^)]*\)[ \t]*\n)'
    r'(?:#define\s+ANDROID_BACKPORT_RESERVED\([^)]*\)[ \t]*\n)'
    r'[ \t]*\n'
    r'(?:#define\s+android_init_vendor_data\([^)]*\)[ \t]*\n)'
    r'(?:#define\s+android_init_oem_data\([^)]*\)[ \t]*\n)'
    r'#endif[ \t]*\n',
    '',
    content,
)

# ----------------------------------------------------------------
# Fallback: if the #ifdef guard line is still present (regex mismatch),
# just comment it out so the block below always compiles.
# ----------------------------------------------------------------
if '#ifdef CONFIG_ANDROID_VENDOR_OEM_DATA' in content:
    content = content.replace(
        '#ifdef CONFIG_ANDROID_VENDOR_OEM_DATA',
        '/* CONFIG_ANDROID_VENDOR_OEM_DATA forced ON for OSS build */\n#if 1',
    )

if content == original:
    print("  android_vendor.h: no change needed (already unconditional or pattern mismatch).")
else:
    HEADER.write_text(content)
    print("  android_vendor.h: patched successfully (vendor data macros unconditional).")

# Verify the key macro is now unconditional
if 'u64 android_vendor_data' in content:
    print("  Verification OK: u64 android_vendor_data fields present.")
else:
    print("  WARNING: u64 android_vendor_data NOT found after patch!")
    sys.exit(1)
