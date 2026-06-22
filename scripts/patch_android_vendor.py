#!/usr/bin/env python3
"""
patch_android_vendor.py

Patches include/linux/android_vendor.h to unconditionally enable
ANDROID_VENDOR_DATA / ANDROID_OEM_DATA macros.

In socrates-t-oss, CONFIG_ANDROID_VENDOR_OEM_DATA has no Kconfig entry,
so make olddefconfig silently drops it. This script removes the #ifdef
guard and the empty stub #else block to force the active definitions.
"""
import sys
from pathlib import Path

def patch_vendor_header():
    # Assume execution from kernel root
    header_path = Path("include/linux/android_vendor.h")

    if not header_path.exists():
        print(f"  [ERROR] {header_path} not found. Are you running this from the kernel root?")
        sys.exit(1)

    try:
        # Read content and handle potential encoding/line ending issues
        content = header_path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        # Fallback for different encodings if necessary
        content = header_path.read_text(encoding='latin-1')

    lines = content.splitlines()

    # Target guard: #ifdef CONFIG_ANDROID_VENDOR_OEM_DATA
    target_ifdef = "CONFIG_ANDROID_VENDOR_OEM_DATA"

    start_idx = -1
    for i, line in enumerate(lines):
        if f"#ifdef {target_ifdef}" in line:
            start_idx = i
            break

    if start_idx == -1:
        print("  [INFO] No #ifdef CONFIG_ANDROID_VENDOR_OEM_DATA found. Already patched or not needed.")
        return

    # Find the corresponding #else and #endif
    # We look for the first #else and first #endif that follow the start_idx
    else_idx = -1
    endif_idx = -1

    for i in range(start_idx + 1, len(lines)):
        stripped = lines[i].strip()
        if stripped == "#else":
            else_idx = i
            # Now find the closing #endif for this block
            for j in range(i + 1, len(lines)):
                if lines[j].strip() == "#endif":
                    endif_idx = j
                    break
            break

    if else_idx == -1 or endif_idx == -1:
        print("  [ERROR] Could not find matching #else/#endif block for the vendor data guard.")
        sys.exit(1)

    # Construct new content:
    # 1. Lines before the #ifdef
    # 2. Lines between #ifdef and #else (the active definitions)
    # 3. Lines after the #endif

    new_lines = lines[:start_idx] + lines[start_idx + 1 : else_idx] + lines[endif_idx + 1:]

    # Add a comment to indicate the change
    new_lines.insert(start_idx, f"/* {target_ifdef} forced ON for OSS build */")

    final_content = "\n".join(new_lines) + "\n"

    header_path.write_text(final_content, encoding='utf-8')
    print(f"  [OK] {header_path} patched successfully (structural removal).")

    # Verification
    if 'u64 android_vendor_data' in final_content:
        print("  [VERIFY] OK: u64 android_vendor_data fields present.")
    else:
        print("  [WARN] Verification failed: u64 android_vendor_data not found in output!")
        sys.exit(1)

if __name__ == "__main__":
    patch_vendor_header()
