#!/usr/bin/env bash
# =============================================================
# apply_susfs.sh  —  Apply SUSFS patches to a 5.10 non-GKI
#                    Xiaomi kernel (socrates / SM8475)
#
# Usage: bash apply_susfs.sh <kernel_src_dir> <susfs4ksu_dir>
#
# Design: uses find/glob to auto-detect real patch filenames,
# so it works regardless of which SUSFS branch was cloned.
# Patch failures warn but do NOT abort (no set -e).
# =============================================================
set -uo pipefail

KERNEL_DIR="${1:?Kernel source dir required}"
SUSFS_DIR="${2:?SUSFS dir required}"

echo "========================================"
echo " SUSFS Patch Applier (auto-detect mode)"
echo " Kernel : $KERNEL_DIR"
echo " SUSFS  : $SUSFS_DIR"
echo "========================================"

echo "==> SUSFS kernel_patches/ contents:"
ls "$SUSFS_DIR/kernel_patches/" 2>/dev/null || echo "  (directory not found)"
echo "==> SUSFS kernel_patches/KernelSU/ contents:"
ls "$SUSFS_DIR/kernel_patches/KernelSU/" 2>/dev/null || echo "  (KernelSU subdir not found)"

cd "$KERNEL_DIR"

# ----------------------------------------------------------------
# Helper: apply a patch — conflict tolerant, never exits on error
# ----------------------------------------------------------------
apply_patch() {
  local patch_file="$1"
  local desc="${2:-$(basename "$patch_file")}"

  if [ ! -f "$patch_file" ]; then
    echo "  [SKIP] Patch file not found: $patch_file"
    return 0
  fi

  echo "  [PATCH] Applying: $desc"
  # Use || true so a non-zero patch exit never kills the script
  if patch -p1 --forward --no-backup-if-mismatch < "$patch_file" 2>&1 || true; then
    echo "  [INFO]  patch command finished for $desc"
  fi

  local rej_count
  rej_count=$(find . -name '*.rej' 2>/dev/null | wc -l)
  if [ "$rej_count" -gt 0 ]; then
    echo "  [WARN] $rej_count .rej file(s) — listing conflicts:"
    find . -name '*.rej' | while read -r rej; do
      echo "    -> $rej"
      head -20 "$rej" | sed 's/^/      | /'
    done
    echo "  [INFO] Non-conflicting hunks were still applied."
    echo "  [INFO] Cleaning up .rej / .orig files..."
    find . -name '*.rej' -delete
    find . -name '*.orig' -delete
  else
    echo "  [OK]   $desc — no conflict files."
  fi
}

# ----------------------------------------------------------------
# 1. Auto-detect and apply the main kernel SUSFS patch
#    File-naming patterns seen across branches:
#      gki-android13-5.10  -> 50_add_susfs_in_gki-android13-5.10.patch
#      gki-android12-5.10  -> 50_add_susfs_in_gki-android12-5.10.patch
#      kernel-5.10 (old)   -> 50_add_susfs_in_kernel-5.10.patch
#      generic             -> 50_add_susfs_in_kernel.patch
# ----------------------------------------------------------------
echo
echo "[1/4] Locating main SUSFS VFS patch..."

MAIN_PATCH=""
# Search for any file matching 50_add_susfs_in_*.patch in kernel_patches/
while IFS= read -r f; do
  # Skip KernelSU-specific patches (those are for step 2)
  case "$f" in
    *KernelSU*|*ksu*|*10_enable*) continue ;;
  esac
  MAIN_PATCH="$f"
  break
done < <(find "$SUSFS_DIR/kernel_patches" -maxdepth 1 -name '50_add_susfs_in_*.patch' 2>/dev/null | sort)

if [ -n "$MAIN_PATCH" ]; then
  echo "  [FOUND] $MAIN_PATCH"
  apply_patch "$MAIN_PATCH" "SUSFS main VFS patch"
else
  echo "  [WARN] No 50_add_susfs_in_*.patch found in $SUSFS_DIR/kernel_patches/"
  echo "  [INFO] Listing all .patch files for debug:"
  find "$SUSFS_DIR" -name '*.patch' 2>/dev/null | sed 's/^/    /'
fi

# ----------------------------------------------------------------
# 2. Auto-detect and apply the KernelSU-side SUSFS patch
#    Locations seen:
#      susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch
#      susfs4ksu/kernel_patches/add_susfs_in_ksu*.patch (older branches)
# ----------------------------------------------------------------
echo
echo "[2/4] Locating KernelSU-side SUSFS patch..."

KSU_PATCH=""
# Prefer the KernelSU/ subdir first (newer branches)
KSU_PATCH_CANDIDATE=$(find "$SUSFS_DIR/kernel_patches/KernelSU" \
  -name '*.patch' 2>/dev/null | sort | head -1)
if [ -n "$KSU_PATCH_CANDIDATE" ]; then
  KSU_PATCH="$KSU_PATCH_CANDIDATE"
else
  # Fall back to top-level kernel_patches/ add_susfs_in_ksu* pattern
  KSU_PATCH=$(find "$SUSFS_DIR/kernel_patches" -maxdepth 1 \
    -name 'add_susfs_in_ksu*.patch' 2>/dev/null | sort | head -1)
fi

if [ -n "$KSU_PATCH" ]; then
  echo "  [FOUND] $KSU_PATCH"
  # Apply inside KernelSU/ subdirectory of the kernel tree
  if [ -d "KernelSU" ]; then
    pushd KernelSU > /dev/null
    apply_patch "../$KSU_PATCH" "KSU-side SUSFS patch"
    popd > /dev/null
  else
    echo "  [WARN] KernelSU/ directory not found in kernel tree — skipping KSU patch"
  fi
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
  # Detect which .c files are actually present
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
      echo "  [INFO] fs/$src not present — skipping $obj"
    fi
  done
else
  echo "  [WARN] fs/Makefile not found!"
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
    echo "  [INFO] include/linux/$hdr not found in SUSFS source (may not be needed)"
  fi
done

echo
echo "========================================"
echo " SUSFS patch application complete!"
echo " Any .rej conflicts were logged above."
echo " mnt_id_reorder risk: default OFF"
echo " (CONFIG_KSU_SUSFS_SUS_MOUNT controls it)"
echo "========================================"
