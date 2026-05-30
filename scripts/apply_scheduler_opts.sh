#!/usr/bin/env bash
# =============================================================
# apply_scheduler_opts.sh  —  Append scheduler + performance
#   optimizations directly into an already-generated out/.config
#
# Usage: bash apply_scheduler_opts.sh <out/.config path>
#
# NOTE: This script must be called AFTER merge_config.sh has
# produced out/.config and BEFORE make olddefconfig.
# olddefconfig will validate / drop unsupported options.
# =============================================================
# Do NOT use set -e here; unsupported configs will be pruned
# by olddefconfig, so we just warn and continue.
set -uo pipefail

CONFIG_FILE="${1:?Usage: apply_scheduler_opts.sh <out/.config path>}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "[ERROR] Config file not found: $CONFIG_FILE"
  exit 1
fi

echo "========================================"
echo " Scheduler & Performance Optimizer"
echo " Target: $CONFIG_FILE"
echo "========================================"

# ----------------------------------------------------------------
# Helper: set or update a single CONFIG_ line in the .config file
# Handles: y / n / numeric / quoted string values
# ----------------------------------------------------------------
set_config() {
  local key="$1"
  local val="$2"
  local full_val

  if [ "$val" = "n" ]; then
    full_val="# $key is not set"
  else
    full_val="${key}=${val}"
  fi

  # Remove any existing entry for this key (both =y and # ... is not set forms)
  sed -i "/^${key}=/d; /^# ${key} is not set/d" "$CONFIG_FILE"
  echo "$full_val" >> "$CONFIG_FILE"
  echo "  [SET] $full_val"
}

echo
echo "--- Energy Aware Scheduling (EAS) ---"
set_config CONFIG_SCHED_EAS y
set_config CONFIG_DEFAULT_USE_ENERGY_AWARE y
set_config CONFIG_ENERGY_MODEL y

echo
echo "--- WALT (Window-Assisted Load Tracking) ---"
set_config CONFIG_SCHED_WALT y

echo
echo "--- Preemption Model: Low-Latency Desktop ---"
# Remove competing preemption options before setting
sed -i '/^CONFIG_PREEMPT_NONE=/d; /^# CONFIG_PREEMPT_NONE/d' "$CONFIG_FILE"
sed -i '/^CONFIG_PREEMPT_VOLUNTARY=/d; /^# CONFIG_PREEMPT_VOLUNTARY/d' "$CONFIG_FILE"
set_config CONFIG_PREEMPT y
set_config CONFIG_PREEMPT_COUNT y

echo
echo "--- Timer Frequency: 300 Hz ---"
sed -i '/^CONFIG_HZ_[0-9]/d; /^# CONFIG_HZ_[0-9]/d; /^CONFIG_HZ=/d' "$CONFIG_FILE"
set_config CONFIG_HZ_300 y
set_config CONFIG_HZ 300

echo
echo "--- CPU Governor: schedutil ---"
set_config CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL y
set_config CONFIG_CPU_FREQ_GOV_SCHEDUTIL y
set_config CONFIG_CPU_FREQ_GOV_PERFORMANCE y
set_config CONFIG_CPU_FREQ_GOV_ONDEMAND y

echo
echo "--- I/O Scheduler: Kyber (UFS 3.1) ---"
set_config CONFIG_MQ_IOSCHED_KYBER y
set_config CONFIG_MQ_IOSCHED_DEADLINE y
set_config CONFIG_IOSCHED_BFQ y

echo
echo "--- TCP: BBR congestion control ---"
set_config CONFIG_TCP_CONG_BBR y
set_config CONFIG_DEFAULT_TCP_CONG '"bbr"'
set_config CONFIG_NET_SCH_FQ y

echo
echo "--- Transparent HugePages (madvise) ---"
set_config CONFIG_TRANSPARENT_HUGEPAGE y
set_config CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS n
set_config CONFIG_TRANSPARENT_HUGEPAGE_MADVISE y

echo
echo "--- CPU Idle governors ---"
set_config CONFIG_CPU_IDLE y
set_config CONFIG_CPU_IDLE_GOV_LADDER y
set_config CONFIG_CPU_IDLE_GOV_MENU y

echo
echo "--- LTO Thin (Clang) ---"
# olddefconfig will drop if unsupported
set_config CONFIG_LTO_CLANG_THIN y

echo
echo "--- Disable debug overhead ---"
set_config CONFIG_DEBUG_PREEMPT n
set_config CONFIG_SCHED_DEBUG n
set_config CONFIG_LATENCYTOP n
set_config CONFIG_PARAVIRT_SPINLOCKS n

echo
echo "========================================"
echo " Scheduler optimizations written to:"
echo " $CONFIG_FILE"
echo " (olddefconfig will validate & prune)"
echo "========================================"
