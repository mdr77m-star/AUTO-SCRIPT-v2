#!/usr/bin/env bash
# ============================================================================
#  HTTP-Custom module — REAL HTTP-custom (Mardhex) protocol customizer.
#  HTTPS -> UDP Custom: client wraps HTTPS in fake UDP packets that look like
#  real UDP traffic (DNS / QUIC / DNS-over-HTTPS).  Works where plain HTTPS
#  is blocked.  Server listens on :443, client connects to target:443.
#  Binary: github.com/http-custom/udp-custom (raw bin/udp-custom-linux-amd64)
# ============================================================================
set -euo pipefail
source /c/Users/IK/Desktop/AUTO-SCRIPT-master/lib/common.sh

readonly HC_DIR="/root/udp"
readonly HC_BIN="${HC_DIR}/udp-custom-linux-amd64"
readonly HC_CFG="${HC_DIR}/config.json"
readonly HC_BIN_URL="https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64"
readonly HC_CFG_URL="https://raw.githubusercontent.com/http-custom/udp-custom/main/config.json"

install_httpcustom() {
  log "INFO" "=== Installing HTTP-Custom (Mardhex) ==="

  apt_update_once
  install_packages iptables netfilter-persistent curl

  ensure_dir "$HC_DIR"

  # fetch binary + config
  log "INFO" "  fetching ${HC_BIN_URL}"
  curl -fsSL "${HC_BIN_URL}" -o "$HC_BIN"
  chmod +x "$HC_BIN"
  log "INFO" "  fetching ${HC_CFG_URL}"
  curl -fsSL "${HC_CFG_URL}" -o "$HC_CFG" || true
  chmod 644 "$HC_CFG"

  # default config: listen :443, password auth, big buffers
  cat > "$HC_CFG" <<JSON
{
  "listen": ":443",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
JSON

  cat > /etc/systemd/system/http-custom.service <<EOF
[Unit]
Description=HTTP-Custom (Mardhex UDP-over-HTTPS)
Documentation=https://github.com/http-custom/udp-custom
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${HC_DIR}
ExecStart=${HC_BIN} server
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 /etc/systemd/system/http-custom.service
  systemctl daemon-reload
  systemctl restart http-custom || true
  systemctl enable http-custom >/dev/null 2>&1 || true

  if wait_port 443 "http-custom" 15; then
    log "INFO" "HTTP-Custom UP on :443"
  else
    log "WARN" "HTTP-Custom port 443 not confirmed - check 'systemctl status http-custom'"
  fi
}
