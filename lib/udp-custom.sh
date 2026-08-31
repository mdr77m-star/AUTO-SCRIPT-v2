#!/usr/bin/env bash
# ============================================================================
#  UDP-Custom module — real Mardhex UDP protocol customizer (already in repo).
#  Re-uses /udp-custom/udp-custom-linux-amd64 + config.json + slowdns.
# ============================================================================
set -euo pipefail
source /c/Users/IK/Desktop/AUTO-SCRIPT-master/lib/common.sh

readonly UCD_DIR="/root/udp"
readonly UCD_BIN="${UCD_DIR}/udp-custom-linux-amd64"
readonly UCD_CFG="${UCD_DIR}/config.json"
readonly UCD_BIN_URL="https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64"
readonly UCD_CFG_URL="https://raw.githubusercontent.com/http-custom/udp-custom/main/config.json"

install_udp_custom() {
  log "INFO" "=== Installing UDP-Custom (Mardhex) ==="

  apt_update_once
  install_packages iptables netfilter-persistent curl

  ensure_dir "$UCD_DIR"

  log "INFO" "  fetching ${UCD_BIN_URL}"
  curl -fsSL "${UCD_BIN_URL}" -o "$UCD_BIN"
  chmod +x "$UCD_BIN"
  log "INFO" "  fetching ${UCD_CFG_URL}"
  curl -fsSL "${UCD_CFG_URL}" -o "$UCD_CFG" || true
  chmod 644 "$UCD_CFG"

  cat > "$UCD_CFG" <<JSON
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
JSON

  cat > /etc/systemd/system/udp-custom.service <<EOF
[Unit]
Description=UDP Custom (Mardhex)
Documentation=https://github.com/http-custom/udp-custom
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${UCD_DIR}
ExecStart=${UCD_BIN} server
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 /etc/systemd/system/udp-custom.service
  systemctl daemon-reload
  systemctl restart udp-custom || true
  systemctl enable udp-custom >/dev/null 2>&1 || true

  if wait_port 36712 "udp-custom" 15; then
    log "INFO" "UDP-Custom UP on :36712"
  else
    log "WARN" "UDP-Custom port 36712 not confirmed - check 'systemctl status udp-custom'"
  fi
}
