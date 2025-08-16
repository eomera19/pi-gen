#!/bin/bash
# Shared logging helper for host + chroot
# Uses ROOTFS_DIR when available, otherwise / for runtime use.
: "${BUILD_LOG:=${ROOTFS_DIR:-/}/etc/image_build.log}"

export BUILD_LOG

log_runtime_step() {
  local step="$1"; shift
  install -d "$(dirname "$BUILD_LOG")"
  # Idempotent: skip if already marked DONE
  if grep -q "DONE ${step}$" "$BUILD_LOG" 2>/dev/null; then
    echo "↳ [$(date -u +%F\ %T)] SKIP ${step}" | tee -a "$BUILD_LOG"
    return 0
  fi
  local t="$(date -u +%F\ %T)"
  echo "==> [$t] START ${step}" | tee -a "$BUILD_LOG"
  if "$@"; then
    echo "    ✅ [$t] DONE ${step}" | tee -a "$BUILD_LOG"
  else
    echo "    ❌ [$t] FAIL ${step}" | tee -a "$BUILD_LOG"
    return 1
  fi
}

export -f log_runtime_step

# --- Colors and formatting ---
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# --- Logging functions ---
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
export -f log_info

log_success() { echo -e "${GREEN}✅ $1${NC}"; }
export -f log_success

log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
export -f log_warning

log_error() { echo -e "${RED}❌ $1${NC}"; }
export -f log_error

log_step() { echo -e "${BLUE}🔧 $1${NC}"; }
export -f log_step

