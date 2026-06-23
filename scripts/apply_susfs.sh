#!/usr/bin/env bash
# ==============================================================================
# apply_susfs.sh  —  Apply SUSFS patches to a 5.10/5.15 non-GKI
#                    Xiaomi kernel (socrates / SM8475)
#
# Usage: bash apply_susfs.sh <kernel_src_dir> <susfs4ksu_dir> [kernel_version]
# ==============================================================================
set -uo pipefail

KERNEL_DIR="${1:?Kernel source dir required}"
SUSFS_DIR="${2:?SUSFS dir required}"
KVER="${3:-5.10}" # Default to 5.10 if not provided

echo "========================================"
echo " SUSFS Patch Applier (Strict Mode)"
echo " Kernel : $KERNEL_DIR"
echo " SUSFS  : $SUSFS_DIR"
echo " Target Version: $KVER"
echo "========================================"

cd "$KERNEL_DIR"

# ----------------------------------------------------------------
# Helper: apply a patch — strict, aborts on conflict/failure
# ----------------------------------------------------------------
apply_patch() {
  local patch_file="$1"
  local desc="${2:-$(basename "$patch_file")}"

  if [ ! -f "$patch_file" ]; then
    echo "  [ERROR] Patch file not found: $patch_file"
    return 1
  fi

  echo "  [PATCH] Applying: $desc"

  # Perform the patch. We do NOT use '|| true' here.
  if patch -p1 --forward --no-backup-if-mismatch < "$patch_file" 2>&1; then
    echo "  [OK]    $desc applied successfully."
  else
    echo "  [FAIL]  $desc failed to apply!"
    return 1
  fi

  local rej_count
  rej_count=$(find . -name '*.rej' 2>/dev/null | wc -l)
  if [ "$rej_count" -gt 0 ]; then
    echo "  [ERROR] $rej_count conflict file(s) (.rej) detected!"
    find . -name '*.rej' | while read -r rej; do
      echo "    -> $rej"
    done
    return 1
  fi
}

# ----------------------------------------------------------------
# 1. Auto-detect and apply the main kernel SUSFS patch
# ----------------------------------------------------------------
echo
echo "[1/4] Locating main SUSFS VFS patch..."

MAIN_PATCH=""
# Priority 1: Look for a patch that explicitly matches the kernel version (e.g., 5.10 or 5.15)
for f in "$SUSFS_DIR"/kernel_patches/50_add_susfs_in_*${KVER}*.patch; do
  [ -e "$f" ] || continue
  filename=$(basename "$f")
  case "$filename" in
    *KernelSU*|*ksu*|*10_enable*) continue ;;
  esac
  MAIN_PATCH="$f"
  break
done

# Priority 2: Fallback to any matching patch if version-specific one isn't found
if [ -z "$MAIN_PATCH" ]; then
  echo "  [INFO] No specific patch for $KVER found, trying generic 50_add_susfs_in_*.patch..."
  for f in "$SUSFS_DIR"/kernel_patches/50_add_susfs_in_*.patch; do
    [ -e "$f" ] || continue
    filename=$(basename "$f")
    case "$filename" in
      *KernelSU*|*ksu*|*10_enable*) continue ;;
    esac
    MAIN_PATCH="$f"
    break
  done
fi

if [ -n "$MAIN_PATCH" ]; then
  echo "  [FOUND] $MAIN_PATCH"
  apply_patch "$MAIN_PATCH" "SUSFS main VFS patch" || exit 1
else
  echo "  [ERROR] No suitable 50_add_susfs_in_*.patch found in $SUSFS_DIR/kernel_patches/"
  exit 1
fi

# ----------------------------------------------------------------
# 2. Auto-detect and apply the KernelSU-side SUSFS patch
# ----------------------------------------------------------------
echo
echo "[2/4] Locating KernelSU-side SUSFS patch..."

KSU_PATCH=""
for f in "$SUSFS_DIR"/kernel_patches/KernelSU/*.patch; do
  [ -e "$f" ] || continue
  KSU_PATCH="$f"
  break
done

if [ -z "$KSU_PATCH" ]; then
  for f in "$SUSFS_DIR"/kernel_patches/add_susfs_in_ksu*.patch; do
    [ -e "$f" ] || continue
    KSU_PATCH="$f"
    break
  done
fi

if [ -n "$KSU_PATCH" ]; then
  echo "  [FOUND] $KSU_PATCH"
  apply_patch "$KSU_PATCH" "KSU-side SUSFS patch" || exit 1
else
  echo "  [INFO] No KernelSU-side patch found (likely already integrated in SukiSU-Ultra)"
fi

# ----------------------------------------------------------------
# 3. Patch fs/Makefile to compile SUSFS .c sources
# ----------------------------------------------------------------
echo
echo "[3/4] Patching fs/Makefile for SUSFS sources..."

FS_MAKEFILE="fs/Makefile"
if [ -f "$FS_MAKEFILE" ]; then
  if [ -n "$(tail -c 1 "$FS_MAKEFILE")" ]; then
    echo "" >> "$FS_MAKEFILE"
  fi

  for src_file in susfs sus_path sus_proc sus_su; do
    obj="${src_file}.o"
    src="${src_file}.c"
    if [ -f "fs/$src" ]; then
      if grep -q "$obj" "$FS_MAKEFILE" 2>/dev/null; then
        echo "  [SKIP] $obj already in fs/Makefile"
      else
        echo "obj-y += $obj" >> "$FS_MAKEFILE"
        echo "  [OK]   Added $obj to fs/Makefile"
      fi
    else
      echo "  [WARN] fs/$src not present — skipping $obj"
    fi
  done
else
  echo "  [ERROR] fs/Makefile not found!"
  exit 1
fi

# ----------------------------------------------------------------
# 4. Verify SUSFS headers are in place
# ----------------------------------------------------------------
echo
echo "[4/4] Verifying SUSFS header installation..."

HEADER_SRC_DIR="$SUSFS_DIR/kernel_patches/include/linux"
for hdr in susfs.h sus_path.h sus_proc.h sus_su.h; do
  if [ -f "include/linux/$hdr" ]; then
    echo "  [OK]   include/linux/$hdr present"
  elif [ -f "$HEADER_SRC_DIR/$hdr" ]; then
    cp -v "$HEADER_SRC_DIR/$hdr" "include/linux/$hdr"
    echo "  [OK]   Copied $hdr from SUSFS source"
  else
    echo "  [ERROR] include/linux/$hdr not found in SUSFS source"
    exit 1
  fi
done

echo
echo "========================================"
echo " SUSFS patch application complete!"
echo "========================================"
