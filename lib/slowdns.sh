#!/usr/bin/env bash
# SlowDNS module - real DNS-over-TLS tunnel (slowdns by fisabiliyusri/SLDNS).
# Server UDP :5300 -> SSH 127.0.0.1:2269. Client tunnels 8.8.8.8:53 through
# NS domain into 127.0.0.1:2222.
set -euo pipefail
source /c/Users/IK/Desktop/AUTO-SCRIPT-master/lib/common.sh

readonly SD_DIR="/etc/slowdns"
readonly SD_NS="${SD_DIR}/nsdomain"
readonly SD_REPO="https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns"
readonly SD_NS_DOMAIN="ns.jubairbro.net"

install_slowdns() {
  log "INFO" "=== Installing SlowDNS ==="

  apt_update_once
  install_packages python3 python3-dnslib net-tools ncurses-utils dnsutils \
    git curl wget screen cron iptables dos2unix gnutls-bin dropbear whois

  if ! grep -q 'Port 2269' /etc/ssh/sshd_config; then
    log "INFO" "Adding SSH ports 2269 / 2266"
    {
      echo "Port 2269"
      echo "Port 2266"
      sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
    } >> /etc/ssh/sshd_config
    systemctl restart ssh || systemctl restart sshd || true
  fi

  iptables -C INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null \
    || iptables -I INPUT -p udp --dport 5300 -j ACCEPT
  iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null \
    || iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
  command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save >/dev/null 2>&1 || true

  ensure_dir "$SD_DIR"; chmod 777 "$SD_DIR"
  local failed=0
  for f in server.key server.pub sldns-server sldns-client; do
    log "INFO" "  fetching ${SD_REPO}/${f}"
    curl -fsSL "${SD_REPO}/${f}" -o "${SD_DIR}/${f}" || { log "WARN" "  failed ${f}"; failed=1; }
  done
  if [[ $failed -ne 0 ]]; then
    log "FATAL" "SlowDNS binary fetch failed"; return 1
  fi
  chmod +x "${SD_DIR}/server.key" "${SD_DIR}/server.pub" \
            "${SD_DIR}/sldns-server" "${SD_DIR}/sldns-client"

  echo "$SD_NS_DOMAIN" > "$SD_NS"
  local nameserver; nameserver="$(cat "$SD_NS")"

  cat > /etc/systemd/system/server-sldns.service <<EOF
[Unit]
Description=Server SlowDNS (SL)
Documentation=https://nekopoi.care
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${SD_DIR}/sldns-server -udp :5300 -privkey-file ${SD_DIR}/server.key ${nameserver} 127.0.0.1:2269
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/client-sldns.service <<EOF
[Unit]
Description=Client SlowDNS (SL)
Documentation=https://nekopoi.care
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${SD_DIR}/sldns-client -udp 8.8.8.8:53 --pubkey-file ${SD_DIR}/server.pub ${nameserver} 127.0.0.1:2222
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 /etc/systemd/system/server-sldns.service /etc/systemd/system/client-sldns.service
  systemctl daemon-reload
  systemctl restart server-sldns || true
  systemctl restart client-sldns || true
  systemctl enable server-sldns client-sldns >/dev/null 2>&1 || true

  if wait_port 5300 "slowdns-server" 15 && wait_port 2222 "slowdns-client" 15; then
    log "INFO" "SlowDNS UP"
  else
    log "WARN" "SlowDNS ports not confirmed - check systemctl status server-sldns"
  fi
  log "INFO" "SlowDNS NS: ${nameserver}"
}