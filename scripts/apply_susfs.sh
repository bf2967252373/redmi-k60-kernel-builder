#!/usr/bin/env bash
# =============================================================
# apply_susfs.sh  —  Apply SUSFS patches to a 5.10 non-GKI
#                    Xiaomi kernel (socrates / SM8475)
#
# Usage: bash apply_susfs.sh <kernel_src_dir> <susfs4ksu_dir>
# =============================================================
set -euo pipefail

KERNEL_DIR="${1:?Kernel source dir required}"
SUSFS_DIR="${2:?SUSFS dir required}"

echo "========================================"
echo " SUSFS Patch Applier for kernel-5.10"
echo " Kernel: $KERNEL_DIR"
echo " SUSFS : $SUSFS_DIR"
echo "========================================"

cd "$KERNEL_DIR"

# ----------------------------------------------------------------
# Helper: apply a patch with conflict tolerance
# ----------------------------------------------------------------
apply_patch() {
  local patch_file="$1"
  local desc="${2:-$(basename $patch_file)}"

  if [ ! -f "$patch_file" ]; then
    echo "  [SKIP] Patch file not found: $patch_file"
    return 0
  fi

  echo "  [PATCH] Applying: $desc"
  if patch -p1 --forward --no-backup-if-mismatch < "$patch_file" 2>&1; then
    echo "  [OK]   $desc applied cleanly."
  else
    echo "  [WARN] $desc had conflicts — checking .rej files..."
    local rej_count
    rej_count=$(find . -name '*.rej' 2>/dev/null | wc -l)
    if [ "$rej_count" -gt 0 ]; then
      echo "  [INFO] $rej_count .rej file(s) found:"
      find . -name '*.rej' | while read rej; do
        echo "    -> $rej"
        echo "    Content preview:"
        head -30 "$rej" | sed 's/^/      | /'
        echo
      done
      echo "  [WARN] Manual merge may be needed for the above conflicts."
      echo "  [INFO] The build will continue — non-conflicting hunks have been applied."
      # Clean up .rej / .orig files to keep tree tidy
      find . -name '*.rej' -delete
      find . -name '*.orig' -delete
    else
      echo "  [OK]   No .rej files — patch applied (possibly already applied)."
    fi
  fi
}

# ----------------------------------------------------------------
# 1. Locate and apply the main SUSFS kernel patch
# ----------------------------------------------------------------
echo
echo "[1/4] Applying main SUSFS VFS patch..."

PATCH_5_10="$SUSFS_DIR/kernel_patches/50_add_susfs_in_kernel-5.10.patch"
PATCH_GENERIC="$SUSFS_DIR/kernel_patches/50_add_susfs_in_kernel.patch"

if [ -f "$PATCH_5_10" ]; then
  apply_patch "$PATCH_5_10" "SUSFS 5.10 main patch"
elif [ -f "$PATCH_GENERIC" ]; then
  apply_patch "$PATCH_GENERIC" "SUSFS generic main patch"
else
  echo "  [WARN] Main SUSFS patch not found — searching..."
  find "$SUSFS_DIR" -name '*.patch' | while read p; do
    echo "  Found: $p"
    apply_patch "$p" "$(basename $p)"
  done
fi

# ----------------------------------------------------------------
# 2. Apply KernelSU-side SUSFS patch (for SukiSU-Ultra)
# ----------------------------------------------------------------
echo
echo "[2/4] Applying KernelSU-side SUSFS patch..."

KSU_PATCH="$SUSFS_DIR/kernel_patches/add_susfs_in_ksu-kernel-5.10.patch"
KSU_PATCH_ALT="$SUSFS_DIR/kernel_patches/add_susfs_in_ksu.patch"

if [ -f "$KSU_PATCH" ]; then
  # Apply into KernelSU subdirectory
  pushd KernelSU > /dev/null
  apply_patch "../$KSU_PATCH" "KSU-side SUSFS 5.10 patch"
  popd > /dev/null
elif [ -f "$KSU_PATCH_ALT" ]; then
  pushd KernelSU > /dev/null
  apply_patch "../$KSU_PATCH_ALT" "KSU-side SUSFS patch"
  popd > /dev/null
else
  echo "  [INFO] No KernelSU-side patch found (may already be integrated in SukiSU-Ultra)"
fi

# ----------------------------------------------------------------
# 3. Patch fs/Makefile to build SUSFS sources
# ----------------------------------------------------------------
echo
echo "[3/4] Patching fs/Makefile for SUSFS sources..."

FS_MAKEFILE="fs/Makefile"
if [ -f "$FS_MAKEFILE" ]; then
  for src_file in susfs.o sus_path.o sus_proc.o sus_su.o; do
    base="${src_file%.o}.c"
    if [ -f "fs/$base" ] && ! grep -q "$src_file" "$FS_MAKEFILE"; then
      echo "obj-y += $src_file" >> "$FS_MAKEFILE"
      echo "  [OK] Added $src_file to fs/Makefile"
    elif [ -f "fs/$base" ]; then
      echo "  [SKIP] $src_file already in fs/Makefile"
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

for hdr in linux/susfs.h linux/sus_path.h linux/sus_proc.h linux/sus_su.h; do
  if [ -f "include/$hdr" ]; then
    echo "  [OK] include/$hdr"
  else
    echo "  [WARN] include/$hdr missing — trying to copy from SUSFS source..."
    BASENAME=$(basename $hdr)
    SRC="$SUSFS_DIR/kernel_patches/include/linux/$BASENAME"
    if [ -f "$SRC" ]; then
      cp -v "$SRC" "include/$hdr"
      echo "  [OK] Copied $BASENAME"
    else
      echo "  [INFO] $BASENAME not found in SUSFS source (may not be needed for this version)"
    fi
  fi
done

echo
echo "========================================"
echo " SUSFS patch application complete!"
echo " Note: Review any .rej conflicts above."
echo " mnt_id_reorder is DISABLED by default"
echo " (enable it later via CONFIG_KSU_SUSFS_SUS_MOUNT)"
echo "========================================"
