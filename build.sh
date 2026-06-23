#!/usr/bin/env bash
# ==============================================================================
# build.sh  —  Master Orchestrator for Redmi K60 Kernel Preparation
#
# This script automates the application of patches and configuration tweaks.
# It MUST be run from the root of the kernel-builder repository.
#
# Usage:
#   bash build.sh <kernel_src_dir> <susfs_dir> [config_path]
# ==============================================================================
set -euo pipefail

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Argument Validation ---
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <kernel_src_dir> <susfs_dir> [config_path]"
  echo "  kernel_src_dir: Absolute path to the kernel source tree"
  echo "  susfs_dir:     Absolute path to the SUSFS4KSU repository"
  echo "  config_path:   (Optional) Path to the .config file to optimize (default: out/.config)"
  exit 1
fi

KERNEL_DIR=$(realpath "$1")
SUSFS_DIR=$(realpath "$2")
CONFIG_PATH="${3:-$KERNEL_DIR/out/.config}"

log "Starting build preparation for Redmi K60..."
log "Kernel Source: $KERNEL_DIR"
log "SUSFS Source : $SUSFS_DIR"

# 1. Verify Directories
[ -d "$KERNEL_DIR" ] || error "Kernel source directory not found: $KERNEL_DIR"
[ -d "$SUSFS_DIR" ] || error "SUSFS directory not found: $SUSFS_DIR"

# 2. Kernel Version Validation
log "Validating kernel version..."
MAKEFILE="$KERNEL_DIR/Makefile"

# Auto-discovery: if Makefile not in root, search first-level subdirs
if [ ! -f "$MAKEFILE" ]; then
  warn "Makefile not found in root, searching subdirectories..."
  # Find the first directory containing a Makefile
  FOUND_MAKEFILE=$(find "$KERNEL_DIR" -maxdepth 2 -name "Makefile" | head -n 1)
  if [ -n "$FOUND_MAKEFILE" ]; then
    log "Found Makefile at: $FOUND_MAKEFILE"
    # Update KERNEL_DIR to the location of the Makefile
    KERNEL_DIR=$(dirname "$FOUND_MAKEFILE")
    MAKEFILE="$FOUND_MAKEFILE"
  else
    echo "--- DEBUG: DIRECTORY SNAPSHOT ---"
    ls -R "$KERNEL_DIR"
    echo "----------------------------------"
    error "Kernel Makefile not found in $KERNEL_DIR or its subdirectories."
  fi
fi


# Extract VERSION and PATCHLEVEL
K_VER=$(grep '^VERSION[ \t]*=[ \t]*' "$MAKEFILE" | awk '{print $3}')
K_PATCH=$(grep '^PATCHLEVEL[ \t]*=[ \t]*' "$MAKEFILE" | awk '{print $3}')

if [[ "$K_VER" != "5" || ( "$K_PATCH" != "10" && "$K_PATCH" != "15" ) ]]; then
  error "Unsupported kernel version: $K_VER.$K_PATCH. This builder is designed for 5.10 or 5.15."
fi
log "Kernel version $K_VER.$K_PATCH verified."

# 3. Apply SUSFS Patches
log "Applying SUSFS patches..."
# We use absolute paths to avoid CWD confusion
bash "scripts/apply_susfs.sh" "$KERNEL_DIR" "$SUSFS_DIR"

# 4. Patch Android Vendor Header
log "Patching android_vendor.h..."
# The python script expects to be run from the kernel root
pushd "$KERNEL_DIR" > /dev/null
python "$(realpath scripts/patch_android_vendor.py)"
popd > /dev/null

# 5. Apply Scheduler Optimizations
# Note: This requires a .config file to already exist (e.g. via make defconfig)
if [ -f "$CONFIG_PATH" ]; then
  log "Applying scheduler optimizations to $CONFIG_PATH..."
  bash "scripts/apply_scheduler_opts.sh" "$CONFIG_PATH"
else
  warn "Config file not found at $CONFIG_PATH. Skipping scheduler optimizations."
  warn "  Please run 'make defconfig' or similar to generate a .config first."
fi

log "=================================================================="
log " Build preparation complete!"
log " You can now proceed with 'make olddefconfig' and 'make -j$(nproc)'"
log "=================================================================="
