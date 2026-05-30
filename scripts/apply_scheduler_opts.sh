#!/usr/bin/env bash
# =============================================================
# apply_scheduler_opts.sh  —  Inject scheduler + performance
#   optimizations into Redmi K60 (socrates/SM8475) defconfig
#
# Usage: bash apply_scheduler_opts.sh <kernel_src_dir> [enable_kpm]
# =============================================================
set -euo pipefail

KERNEL_DIR="${1:?Kernel source dir required}"
ENABLE_KPM="${2:-true}"

echo "========================================"
echo " Scheduler & Performance Optimizer"
echo " Kernel : $KERNEL_DIR"
echo "========================================"

cd "$KERNEL_DIR"

# ----------------------------------------------------------------
# Find the right defconfig
# ----------------------------------------------------------------
find_defconfig() {
  local candidates=(
    "arch/arm64/configs/vendor/socrates_defconfig"
    "arch/arm64/configs/socrates_defconfig"
    "arch/arm64/configs/vendor/lahaina_defconfig"
  )
  for c in "${candidates[@]}"; do
    if [ -f "$c" ]; then
      echo "$c"
      return 0
    fi
  done
  # Search broadly
  find arch/arm64/configs -name '*socrat*' 2>/dev/null | head -1
}

DEFCONFIG=$(find_defconfig)
if [ -z "$DEFCONFIG" ]; then
  echo "[WARN] Could not find socrates defconfig. Scheduler opts will be applied at build-time via olddefconfig."
  exit 0
fi

echo "[OK] Using defconfig: $DEFCONFIG"

# ----------------------------------------------------------------
# Helper: set or update a CONFIG_ line
# ----------------------------------------------------------------
set_config() {
  local key="$1"
  local val="$2"   # y, n, m, or =XXXX
  local full_val

  if [ "$val" = "n" ]; then
    full_val="# $key is not set"
  elif [[ "$val" =~ ^[0-9] ]]; then
    full_val="$key=$val"
  elif [ "${val:0:1}" = '"' ]; then
    full_val="$key=$val"
  else
    full_val="${key}=${val}"
  fi

  # Remove existing line (both enabled and disabled forms)
  sed -i "/^${key}[= ]/d; /^# ${key} is not set/d" "$DEFCONFIG"
  echo "$full_val" >> "$DEFCONFIG"
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
set_config CONFIG_WALT_TUNE_UTIL_UP_THRESHOLD_SILVER "95"
set_config CONFIG_WALT_TUNE_UTIL_UP_THRESHOLD_GOLD "95"

echo
echo "--- Preemption Model (Low-Latency Desktop) ---"
# Remove all preemption alternatives first
sed -i '/CONFIG_PREEMPT_NONE/d; /CONFIG_PREEMPT_VOLUNTARY/d; /CONFIG_PREEMPT[^_]/d' "$DEFCONFIG"
set_config CONFIG_PREEMPT y
set_config CONFIG_PREEMPT_COUNT y

echo
echo "--- Timer Frequency (300 Hz for smoother scheduling) ---"
# Clear other HZ options
sed -i '/CONFIG_HZ_[0-9]*/d; /CONFIG_HZ=/d' "$DEFCONFIG"
set_config CONFIG_HZ_300 y
set_config CONFIG_HZ 300

echo
echo "--- CPU Governor: schedutil (best for EAS) ---"
set_config CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL y
set_config CONFIG_CPU_FREQ_GOV_SCHEDUTIL y
set_config CONFIG_CPU_FREQ_GOV_PERFORMANCE y
set_config CONFIG_CPU_FREQ_GOV_ONDEMAND y

echo
echo "--- I/O Scheduler: Kyber (optimized for UFS 3.1) ---"
set_config CONFIG_MQ_IOSCHED_KYBER y
set_config CONFIG_MQ_IOSCHED_DEADLINE y
set_config CONFIG_IOSCHED_BFQ y

echo
echo "--- TCP Congestion Control: BBR ---"
set_config CONFIG_TCP_CONG_BBR y
set_config CONFIG_DEFAULT_TCP_CONG "\"bbr\""
set_config CONFIG_NET_SCH_FQ y

echo
echo "--- Memory & Latency ---"
set_config CONFIG_TRANSPARENT_HUGEPAGE y
set_config CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS n
set_config CONFIG_TRANSPARENT_HUGEPAGE_MADVISE y
set_config CONFIG_ARCH_WANT_HUGE_PMD_SHARE y

echo
echo "--- Compiler optimizations ---"
# O3 only if supported; most Qualcomm kernels default to O2
if grep -q 'CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE' arch/arm64/configs/Kconfig.* 2>/dev/null || \
   grep -rq 'CC_OPTIMIZE' Kconfig 2>/dev/null; then
  set_config CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE y
fi

echo
echo "--- CPU idle: Ladder + CPUIDLE tuning ---"
set_config CONFIG_CPU_IDLE y
set_config CONFIG_CPU_IDLE_GOV_LADDER y
set_config CONFIG_CPU_IDLE_GOV_MENU y

echo
echo "--- LTO (Link-Time Optimization): thin LTO if Clang ---"
# Only enable if kernel supports it; safe to set, olddefconfig will drop if unsupported
set_config CONFIG_LTO_CLANG_THIN y

echo
echo "--- Misc performance hardening ---"
set_config CONFIG_SCHED_CLUSTER y 2>/dev/null || true   # cluster-aware scheduling
set_config CONFIG_SCHED_CORE y 2>/dev/null || true
set_config CONFIG_PARAVIRT_SPINLOCKS n
set_config CONFIG_DEBUG_PREEMPT n
set_config CONFIG_SCHED_DEBUG n
set_config CONFIG_LATENCYTOP n

echo
echo "========================================"
echo " Scheduler optimizations applied!"
echo " Defconfig: $DEFCONFIG"
echo "========================================"
