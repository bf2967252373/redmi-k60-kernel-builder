#!/usr/bin/env bash
# ==============================================================================
# apply_susfs.sh  —  Apply SUSFS patches to a 5.10/5.15 non-GKI
#                    Xiaomi kernel (socrates / SM8475)
#
# Usage: bash apply_susfs.sh <kernel_src_dir> <susfs4ksu_dir> [kernel_version]
#
# Self-contained: this script both copies SUSFS source files AND applies
# patches, so it works correctly regardless of which workflow calls it.
# ==============================================================================
set -uo pipefail

KERNEL_DIR="$(realpath "${1:?'kernel_src_dir is required as first argument'}")"
SUSFS_DIR="$(realpath "${2:?'susfs4ksu_dir is required as second argument'}")"
KVER="${3:-5.15}"  # Default to 5.15 (socrates/SM8475)

echo "========================================"
echo " SUSFS Patch Applier (Resilient Mode)"
echo " Kernel : $KERNEL_DIR"
echo " SUSFS  : $SUSFS_DIR"
echo " Target Version: $KVER"
echo "========================================"

cd "$KERNEL_DIR"

# ----------------------------------------------------------------
# Helper: apply a patch — resilient, warns on conflict but continues
# $1 = patch file path
# $2 = human-readable description
# $3 = working directory to apply from (default: KERNEL_DIR)
# ----------------------------------------------------------------
apply_patch() {
  local patch_file="$1"
  local desc="${2:-$patch_file}"
  local work_dir="${3:-$KERNEL_DIR}"

  if [ ! -f "$patch_file" ]; then
    echo "  [ERROR] Patch file not found: $patch_file"
    return 1
  fi

  echo "  [PATCH] Applying: $desc"

  # --fuzz=3 allows slight line offsets common in vendor/non-GKI kernels
  if (cd "$work_dir" && patch -p1 --forward --fuzz=3 --no-backup-if-mismatch < "$patch_file" 2>&1); then
    echo "  [OK]    $desc applied successfully."
  else
    echo "  [WARN]  $desc had some conflicts (Hunks failed)."
    echo "  [INFO]  Continuing anyway... (Resilient Mode)"
  fi

  # Remove patch artefacts so they never pollute the build
  find "$work_dir" -name '*.rej'  -delete
  find "$work_dir" -name '*.orig' -delete
}

# ----------------------------------------------------------------
# 1. Auto-detect and apply the main kernel VFS patch
# ----------------------------------------------------------------
echo
echo "[1/5] Locating main SUSFS VFS patch..."

MAIN_PATCH=""
for f in "$SUSFS_DIR"/kernel_patches/50_add_susfs_in_*.patch; do
  [ -e "$f" ] || continue
  filename=$(basename "$f")
  # Skip the KSU-side patch that lives in the same glob space
  case "$filename" in
    *KernelSU*|*ksu*|*10_enable*) continue ;;
  esac
  MAIN_PATCH="$f"
  break
done

if [ -n "$MAIN_PATCH" ]; then
  echo "  [FOUND] $MAIN_PATCH"
  apply_patch "$MAIN_PATCH" "SUSFS main VFS patch" "$KERNEL_DIR"
else
  echo "  [ERROR] No suitable 50_add_susfs_in_*.patch found in $SUSFS_DIR/kernel_patches/"
  exit 1
fi

# ----------------------------------------------------------------
# 2. Auto-detect and apply the KernelSU-side SUSFS patch
#
# IMPORTANT: The KSU patch targets KernelSU's internal directory
# layout (kernel/Kbuild, kernel/core/init.c, etc.), NOT the Linux
# kernel tree. It must be applied from inside the KernelSU clone.
#
# For SukiSU-Ultra, SUSFS is already pre-integrated, so these
# failures are expected and are handled by resilient mode.
# ----------------------------------------------------------------
echo
echo "[2/5] Locating KernelSU-side SUSFS patch..."

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
  if [ -d "$KERNEL_DIR/KernelSU" ]; then
    # Apply inside the KernelSU clone where the target files actually live
    echo "  [INFO]  KernelSU clone found — applying patch inside $KERNEL_DIR/KernelSU/"
    apply_patch "$KSU_PATCH" "KSU-side SUSFS patch" "$KERNEL_DIR/KernelSU"
  else
    echo "  [INFO]  KernelSU not yet cloned — KSU patch skipped (SukiSU-Ultra has SUSFS pre-integrated)"
  fi
else
  echo "  [INFO] No KernelSU-side patch found (already integrated in SukiSU-Ultra)"
fi

# ----------------------------------------------------------------
# 3. Copy SUSFS .c source files into the kernel fs/ directory
#
# The main patch (step 1) only MODIFIES existing kernel files by
# inserting hooks/includes.  It does NOT create the SUSFS source
# files (susfs.c, sus_path.c, sus_proc.c, sus_su.c).  These must
# be explicitly copied from the SUSFS repo.
# ----------------------------------------------------------------
echo
echo "[3/5] Copying SUSFS .c source files into kernel fs/..."

FS_SRC_DIR="$SUSFS_DIR/kernel_patches/fs"
FS_DST_DIR="$KERNEL_DIR/fs"

if [ -d "$FS_SRC_DIR" ]; then
  copied=0
  for f in "$FS_SRC_DIR"/*.c; do
    [ -f "$f" ] || continue
    fname=$(basename "$f")
    if [ -f "$FS_DST_DIR/$fname" ]; then
      echo "  [SKIP] fs/$fname already present"
    else
      cp -v "$f" "$FS_DST_DIR/$fname"
      echo "  [OK]   Copied fs/$fname from SUSFS source"
      copied=$((copied + 1))
    fi
  done
  if [ "$copied" -eq 0 ]; then
    echo "  [INFO] No new .c files to copy (already present, or this SUSFS version embeds them in the patch)"
  fi
else
  echo "  [WARN] $FS_SRC_DIR not found — .c files not copied."
  echo "  [WARN] If susfs.c / sus_path.c etc. are absent, the kernel build will fail."
fi

# ----------------------------------------------------------------
# 4. Patch fs/Makefile to compile any present SUSFS .c sources
# ----------------------------------------------------------------
echo
echo "[4/5] Patching fs/Makefile for SUSFS sources..."

FS_MAKEFILE="fs/Makefile"
if [ -f "$FS_MAKEFILE" ]; then
  # Ensure file ends with a newline before appending
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
      echo "  [INFO] fs/$src not present — skipping $obj (may be embedded in susfs.c)"
    fi
  done
else
  echo "  [ERROR] fs/Makefile not found!"
  exit 1
fi

# ----------------------------------------------------------------
# 5. Verify / install SUSFS headers
#
# susfs.h        → REQUIRED  (hard fail if missing)
# sus_path.h  }
# sus_proc.h  }  OPTIONAL  (susfs4ksu >= 1.5 consolidates all
# sus_su.h    }              declarations into susfs.h alone)
# ----------------------------------------------------------------
echo
echo "[5/5] Verifying SUSFS header installation..."

HEADER_SRC_DIR="$SUSFS_DIR/kernel_patches/include/linux"

# ---- Required header ----
for hdr in susfs.h; do
  if [ -f "include/linux/$hdr" ]; then
    echo "  [OK]   include/linux/$hdr present"
  elif [ -f "$HEADER_SRC_DIR/$hdr" ]; then
    cp -v "$HEADER_SRC_DIR/$hdr" "include/linux/$hdr"
    echo "  [OK]   Copied $hdr from SUSFS source"
  else
    echo "  [ERROR] include/linux/$hdr not found — this file is REQUIRED!"
    exit 1
  fi
done

# ---- Optional legacy headers (may be gone in susfs4ksu >= 1.5) ----
for hdr in sus_path.h sus_proc.h sus_su.h; do
  if [ -f "include/linux/$hdr" ]; then
    echo "  [OK]   include/linux/$hdr present"
  elif [ -f "$HEADER_SRC_DIR/$hdr" ]; then
    cp -v "$HEADER_SRC_DIR/$hdr" "include/linux/$hdr"
    echo "  [OK]   Copied $hdr from SUSFS source"
  else
    echo "  [INFO] include/linux/$hdr not in SUSFS source — OK (consolidated into susfs.h in newer versions)"
  fi
done

echo
echo "========================================"
echo " SUSFS patch application complete!"
echo "========================================"
