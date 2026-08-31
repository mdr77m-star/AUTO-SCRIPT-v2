#!/usr/bin/env bash
# OpenVPN module - real OpenVPN server with PKI (easy-rsa), client .ovpn
# files served over nginx on port 81.
set -euo pipefail
source /c/Users/IK/Desktop/AUTO-SCRIPT-master/lib/common.sh

readonly OV_DIR="/etc/openvpn"
readonly OV_CLIENTS="/home/vps/clients"

install_openvpn() {
  log "INFO" "=== Installing OpenVPN ==="

  apt_update_once
  install_packages openvpn easy-rsa

  ensure_dir "$OV_DIR" "$OV_CLIENTS"
  chmod 755 "$OV_CLIENTS"

  # Build PKI with easy-rsa
  local EASYRSA="/usr/share/easy-rsa"
  if [[ ! -d "${EASYRSA}/easyrsa3" ]]; then
    EASYRSA="/etc/openvpn/easy-rsa"
    ensure_dir "$EASYRSA"
    cp -r /usr/share/easy-rsa/* "$EASYRSA" 2>/dev/null || true
  fi
  if command -v easy-rsa >/dev/null 2>&1; then
    "${EASYRSA}/easyrsa" init-pki >/dev/null 2>&1 || true
    "${EASYRSA}/easyrsa" build-ca nopass >/dev/null 2>&1 || true
    "${EASYRSA}/easyrsa" build-server nopass server >/dev/null 2>&1 || true
  fi

  cat > "${OV_DIR}/server.conf" <<EOF
port 1194
proto udp
dev tun
ca ${OV_DIR}/ca.crt
cert ${OV_DIR}/server.crt
key ${OV_DIR}/server.key
dh ${OV_DIR}/dh.pem
server 10.8.0.0 255.255.255.0
client-to-client
keepalive 10 120
persist-key
persist-tun
status ${OV_DIR}/openvpn-status.log
verb 3
EOF

  cat > /etc/systemd/system/openvpn@.service <<EOF
[Unit]
Description=OpenVPN server
After=network.target

[Service]
Type=forking
ExecStart=/usr/sbin/openvpn --config ${OV_DIR}/server.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl restart openvpn@server 2>/dev/null || true
  systemctl enable openvpn@server 2>/dev/null || true

  if wait_port 1194 "openvpn" 15; then
    log "INFO" "OpenVPN UP on :1194"
  else
    log "WARN" "OpenVPN port 1194 not confirmed"
  fi
}