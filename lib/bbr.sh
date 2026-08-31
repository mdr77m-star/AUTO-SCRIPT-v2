#!/usr/bin/env bash
# BBR module - TCP congestion control + qdisc optimization.
set -euo pipefail
source /c/Users/IK/Desktop/AUTO-SCRIPT-master/lib/common.sh

install_bbr() {
  log "INFO" "=== Applying BBR TCP congestion control ==="

  local cc; cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  if [[ "$cc" == "bbr" || "$cc" == "bbrplus" ]]; then
    log "INFO" "BBR already active: ${cc}"
    return 0
  fi

  cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl -p >/dev/null 2>&1 || true
  cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  local qdisc; qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
  log "INFO" "TCP congestion: ${cc}, qdisc: ${qdisc}"
}