#!/usr/bin/env bash
# ============================================================================
#  AUTO-SCRIPT — shared library (sourced by setup.sh and all menu scripts)
# ============================================================================
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8

readonly REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/jubairbro/AUTO-SCRIPT/master}"

# ---- logging -----------------------------------------------------------------
log() {
  local level="${1:?}"; shift
  local msg="$*"
  local ts; ts="$(date '+%H:%M:%S')"
  printf '\033[1;36m[%s]\033[0m \033[1;32m[%s]\033[0m %s\n' "$ts" "$level" "$msg"
}

# ---- preflight ---------------------------------------------------------------
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log "FATAL" "Run as root: sudo -s"
    exit 1
  fi
}

detect_os() {
  . /etc/os-release 2>/dev/null || true
  DISTRO="${ID:-unknown}"
  VER="${VERSION_ID:-unknown}"
  log "INFO" "OS: ${DISTRO} ${VER}"
  case "${DISTRO}" in
    debian|ubuntu) ;;
    *) log "WARN" "Unsupported distro (${DISTRO}); script may behave unexpectedly" ;;
  esac
}

check_openvz() {
  if [[ "$(systemd-detect-virt 2>/dev/null || echo none)" == "openvz" ]]; then
    log "FATAL" "OpenVZ not supported"
    exit 1
  fi
}

disable_ipv6() {
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
  if ! grep -q 'disable_ipv6' /etc/sysctl.conf 2>/dev/null; then
    echo 'net.ipv6.conf.all.disable_ipv6=1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.default.disable_ipv6=1' >> /etc/sysctl.conf
  fi
}

# ---- package management ------------------------------------------------------
apt_update_once() {
  apt-get update -y
}

install_packages() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  log "INFO" "Installing packages: ${pkgs[*]}"
  apt-get install -y "${pkgs[@]}" || {
    log "WARN" "apt install failed, retrying after update"
    apt-get update -y
    apt-get install -y "${pkgs[@]}"
  }
}

ensure_dir() { mkdir -p "$1"; }

# ---- network helpers ---------------------------------------------------------
get_public_ip() {
  curl -fsS -m 10 ifconfig.me 2>/dev/null \
    || curl -fsS -m 10 icanhazip.com 2>/dev/null \
    || echo "unknown"
}

wait_port() {
  local port="$1" svc="${2:-}" timeout="${3:-30}"
  local i=0
  while ! (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null; do
    i=$((i + 1))
    if [[ $i -ge $timeout ]]; then
      exec 3>&- 3<&- 2>/dev/null || true
      log "WARN" "Port ${port} (${svc}) not open after ${timeout}s"
      return 1
    fi
    sleep 1
  done
  exec 3>&- 3<&- 2>/dev/null || true
  log "INFO" "Port ${port} (${svc}) open"
}

systemctl_restart() {
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl restart "$1" >/dev/null 2>&1 || true
  systemctl enable "$1" >/dev/null 2>&1 || true
}

# ---- random helpers ----------------------------------------------------------
random_password() {
  local len="${1:-16}"
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len" || true
}

random_subdomain() {
  local len="${1:-10}"
  tr -dc 'a-z0-9' </dev/urandom | head -c "$len" || true
}

# ---- misc -------------------------------------------------------------------
cleanup_temp_files() {
  local f
  for f in "$@"; do
    [[ -f "$f" ]] && rm -f "$f"
  done
}

