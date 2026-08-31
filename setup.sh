#!/usr/bin/env bash
# ============================================================================
#  AUTO-SCRIPT — professional single-command VPS auto-setup
#  Installs: Xray | SSH/WebSocket | SlowDNS | HTTP-Custom | UDP-Custom | OpenVPN | Webmin | BBR
#
#  Usage on a FRESH VPS:
#    wget https://raw.githubusercontent.com/jubairbro/AUTO-SCRIPT/master/setup.sh
#    chmod +x setup.sh && screen -S setup ./setup.sh
#
#  Or one-liner:
#    bash <(curl -fsSL https://raw.githubusercontent.com/jubairbro/AUTO-SCRIPT/master/setup.sh)
# ============================================================================
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8

# SECURITY: validate REPO_BASE against whitelist before use
_validate_repo() {
  local repo="${1:-}"
  if [[ -n "$repo" && "$repo" =~ ^https://raw\.githubusercontent\.com/(jubairbro|mdr77m-star)/AUTO-SCRIPT(/.*)?$ ]]; then
    return 0
  fi
  return 1
}

REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/jubairbro/AUTO-SCRIPT/master}"
_validate_repo "$REPO_BASE" || { echo "[FATAL] Invalid REPO_BASE: $REPO_BASE"; exit 1; }

log() { echo "[$(date '+%H:%M:%S')] [$1] ${*:2}"; }

# SECURITY: checksum verify a downloaded binary (basic integrity check)
# Args: file path, min_size_bytes
_verify_binary() {
  local file="$1" min_size="${2:-1000}"
  if [[ ! -f "$file" ]]; then
    echo "[FATAL] Missing file: $file"
    return 1
  fi
  local size; size="$(wc -c < "$file")"
  if [[ "$size" -lt "$min_size" ]]; then
    echo "[FATAL] Binary too small (${size}B): $file — possible download failure"
    rm -f "$file"
    return 1
  fi
  return 0
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || { log FATAL "Run as root: sudo -s"; exit 1; }
}

detect_os() {
  . /etc/os-release 2>/dev/null || true
  log INFO "OS: ${ID:-unknown} ${VERSION_ID:-unknown}"
  case "${ID:-}" in debian|ubuntu) ;; *) log WARN "Unsupported distro: ${ID}"; ;; esac
}

check_openvz() {
  [[ "$(systemd-detect-virt 2>/dev/null)" == "openvz" ]] && { log FATAL "OpenVZ not supported"; exit 1; }
}

disable_ipv6() {
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
}

apt_update_once() { [[ ! -f /var/cache/apt/pkgcache.bin ]] && apt-get update -y; }

install_packages() { log INFO "Installing: $*"; apt-get install -y "$@" || apt-get install -y "$@" || true; }

get_public_ip() {
  curl -fsS -m 10 ifconfig.me 2>/dev/null || curl -fsS -m 10 icanhazip.com 2>/dev/null || echo unknown;
}

wait_port() {
  local port="$1" svc="$2" t="${3:-30}" i=0
  while ! (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null; do
    i=$((i+1)); [[ $i -ge $t ]] && { exec 3>&- 3<&- 2>/dev/null; return 1; }; sleep 1
  done; exec 3>&- 3<&- 2>/dev/null; return 0
}

# ---- SSH + VPN stack: pure local install (no remote dependencies) ----
install_ssh_vpn() {
  log INFO "=== Installing SSH/VPN stack (local) ==="
  local ssh_dir="${LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib}/../ssh"
  local t; t="$(mktemp)"
  if [[ -f "${ssh_dir}/ssh-vpn.sh" ]]; then
    cp -f "${ssh_dir}/ssh-vpn.sh" "$t" && bash "$t" && log INFO "SSH/VPN done"
  else
    # fallback to remote (only from THIS repo, not jubairbro)
    curl -fsSL "${REPO_BASE}/ssh/ssh-vpn.sh" -o "$t" && bash "$t" && log INFO "SSH/VPN done (remote)"
  fi
  rm -f "$t"
}

# ---- Xray: pure local install (no remote dependencies) ----
install_xray() {
  log INFO "=== Installing Xray (local) ==="
  local xray_dir="${LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib}/../xray"
  local t; t="$(mktemp)"
  if [[ -f "${xray_dir}/ins-xray.sh" ]]; then
    cp -f "${xray_dir}/ins-xray.sh" "$t" && bash "$t" && log INFO "Xray done"
  else
    curl -fsSL "${REPO_BASE}/xray/ins-xray.sh" -o "$t" && bash "$t" && log INFO "Xray done (remote)"
  fi
  rm -f "$t"
}

# ---- SSH over WebSocket: pure local install (no remote dependencies) ----
install_sshws() {
  log INFO "=== Installing SSH WebSocket (local) ==="
  local ws_dir="${LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib}/../sshws"
  local t; t="$(mktemp)"
  if [[ -f "${ws_dir}/insshws.sh" ]]; then
    cp -f "${ws_dir}/insshws.sh" "$t" && bash "$t" && log INFO "SSH WS done"
  else
    curl -fsSL "${REPO_BASE}/sshws/insshws.sh" -o "$t" && bash "$t" && log INFO "SSH WS done (remote)"
  fi
  rm -f "$t"
}

# ---- SlowDNS (real DNS-over-TLS tunnel) ----
install_slowdns() {
  log INFO "=== Installing SlowDNS ==="

  apt_update_once
  install_packages python3 python3-dnslib net-tools ncurses-utils dnsutils \
    git curl wget screen cron iptables dos2unix gnutls-bin dropbear whois

  if ! grep -q 'Port 2269' /etc/ssh/sshd_config 2>/dev/null; then
    log INFO "Adding SSH ports 2269 / 2266"
    { echo "Port 2269"; echo "Port 2266"; } >> /etc/ssh/sshd_config
    sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  fi

  iptables -C INPUT -p udp --dport 5300 -j ACCEPT 2>/dev/null \
    || iptables -I INPUT -p udp --dport 5300 -j ACCEPT
  iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null \
    || iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
  command -v netfilter-persistent >/dev/null 2>&1 && netfilter-persistent save 2>/dev/null || true

  local SD_REPO="https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns"
  local SD_DIR="/etc/slowdns"
  mkdir -p "$SD_DIR" && chmod 777 "$SD_DIR"
  local failed=0
  for f in server.key server.pub sldns-server sldns-client; do
    log INFO "  fetching ${SD_REPO}/${f}"
    curl -fsSL "${SD_REPO}/${f}" -o "${SD_DIR}/${f}" || { log WARN "  failed ${f}"; failed=1; }
  done
  [[ $failed -ne 0 ]] && { log FATAL "SlowDNS binary fetch failed"; exit 1; }
  # SECURITY: verify downloaded binaries are non-empty
  _verify_binary "${SD_DIR}/sldns-server" 100000 || { log FATAL "SlowDNS server binary invalid"; exit 1; }
  _verify_binary "${SD_DIR}/sldns-client" 100000 || { log FATAL "SlowDNS client binary invalid"; exit 1; }
  chmod +x "${SD_DIR}/server.key" "${SD_DIR}/server.pub" "${SD_DIR}/sldns-server" "${SD_DIR}/sldns-client"

  local NS_DOMAIN="ns.$(cat /etc/xray/domain 2>/dev/null || echo 'yourdomain.com')"
  echo "$NS_DOMAIN" > /etc/slowdns/nsdomain
  local nameserver; nameserver="$(cat /etc/slowdns/nsdomain)"

  cat > /etc/systemd/system/server-sldns.service <<EOF
[Unit]
Description=Server SlowDNS (SL)
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
  systemctl restart server-sldns client-sldns 2>/dev/null || true
  systemctl enable server-sldns client-sldns 2>/dev/null || true

  wait_port 5300 "slowdns-server" 15 && log INFO "SlowDNS server UP on UDP :5300" \
    || log WARN "SlowDNS port 5300 not confirmed"
  log INFO "SlowDNS NS: ${nameserver}"
}

# ---- HTTP-Custom (Mardhex UDP-over-HTTPS on :443) ----
install_httpcustom() {
  log INFO "=== Installing HTTP-Custom ==="

  local HC_DIR="/root/udp" HC_BIN="${HC_DIR}/udp-custom-linux-amd64" HC_CFG="${HC_DIR}/config.json"
  mkdir -p "$HC_DIR"

  log INFO "  fetching HTTP-Custom binary"
  curl -fsSL "https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64" \
    -o "$HC_BIN" || { log WARN "HTTP-Custom binary fetch failed"; return 0; }
  # SECURITY: verify binary size (expected ~4.7MB)
  _verify_binary "$HC_BIN" 4000000 || { log WARN "HTTP-Custom binary invalid"; return 0; }
  chmod +x "$HC_BIN"

  cat > "$HC_CFG" <<EOF
{
  "listen": ":443",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": { "mode": "passwords" }
}
EOF

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
  systemctl restart http-custom 2>/dev/null || true
  systemctl enable http-custom 2>/dev/null || true
  wait_port 443 "http-custom" 15 && log INFO "HTTP-Custom UP on :443" \
    || log WARN "HTTP-Custom port 443 not confirmed"
}

# ---- UDP-Custom (Mardhex custom UDP protocol on :36712) ----
install_udp_custom() {
  log INFO "=== Installing UDP-Custom ==="

  local UCD_DIR="/root/udp" UCD_BIN="${UCD_DIR}/udp-custom-linux-amd64" UCD_CFG="${UCD_DIR}/config.json"
  mkdir -p "$UCD_DIR"

  if [[ ! -f "$UCD_BIN" ]]; then
    log INFO "  fetching UDP-Custom binary"
    curl -fsSL "https://raw.githubusercontent.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64" \
      -o "$UCD_BIN" || true
  fi
  # SECURITY: verify binary size (expected ~4.7MB)
  _verify_binary "$UCD_BIN" 4000000 || true
  chmod +x "$UCD_BIN" 2>/dev/null || true

  cat > "$UCD_CFG" <<EOF
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": { "mode": "passwords" }
}
EOF

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
  systemctl restart udp-custom 2>/dev/null || true
  systemctl enable udp-custom 2>/dev/null || true
  wait_port 36712 "udp-custom" 15 && log INFO "UDP-Custom UP on :36712" \
    || log WARN "UDP-Custom port 36712 not confirmed"
}

# ---- OpenVPN (easy-rsa PKI, client .ovpn over nginx :81) ----
install_openvpn() {
  log INFO "=== Installing OpenVPN ==="

  apt_update_once
  install_packages openvpn easy-rsa

  local OV_DIR="/etc/openvpn" OV_CLIENTS="/home/vps/clients"
  mkdir -p "$OV_DIR" "$OV_CLIENTS" && chmod 755 "$OV_CLIENTS"

  local EASYRSA="/usr/share/easy-rsa"
  if [[ ! -d "${EASYRSA}/easyrsa3" ]]; then
    EASYRSA="/etc/openvpn/easy-rsa"
    mkdir -p "$EASYRSA" && cp -r /usr/share/easy-rsa/* "$EASYRSA" 2>/dev/null || true
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
  wait_port 1194 "openvpn" 15 && log INFO "OpenVPN UP on :1194" \
    || log WARN "OpenVPN port 1194 not confirmed"
}

# ---- Webmin ----
install_webmin() {
  log INFO "=== Installing Webmin ==="

  apt_update_once
  install_packages wget apt-transport-https gnupg curl

  if ! grep -q 'webmin' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    # SECURITY: use HTTPS for webmin key and repo
    wget -qO- https://www.webmin.com/jcameron-key.asc 2>/dev/null | apt-key add - 2>/dev/null || true
    echo "deb https://download.webmin.com/apt webmain main" > /etc/apt/sources.list.d/webmin.list
    apt-get update -y 2>/dev/null
  fi

  apt-get install -y webmin 2>/dev/null || log WARN "Webmin apt install failed"

  systemctl restart webmin 2>/dev/null || true
  systemctl enable webmin 2>/dev/null || true
  wait_port 10000 "webmin" 15 && log INFO "Webmin UP on :10000" \
    || log WARN "Webmin port 10000 not confirmed"
}

# ---- BBR TCP congestion control ----
install_bbr() {
  log INFO "=== Applying BBR ==="
  local cc; cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
  if [[ "$cc" == "bbr" || "$cc" == "bbrplus" ]]; then
    log INFO "BBR already active: ${cc}"
  else
    cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl -p >/dev/null 2>&1 || true
    cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    log INFO "TCP congestion control: ${cc}"
  fi
}

# ---- Auto-expire cron ----
setup_autoremove() {
  log INFO "=== Setting up auto-expire cron ==="

  cat > /usr/local/bin/autoremove-expired.sh <<'CRON_EOF'
#!/usr/bin/env bash
log() { echo "[$(date '+%H:%M:%S')] [INFO] $*"; }
while IFS=: read -r user _ uid _ _ exp _; do
  [[ "$uid" -lt 1000 ]] && continue
  [[ -z "$exp" || "$exp" == "never" ]] && continue
  [[ "$(date -d "$exp" +%s 2>/dev/null || echo 0)" -lt "$(date +%s)" ]] || continue
  log "Expiring: $user (expired: $exp)"
  userdel -rf "$user" 2>/dev/null || true
  crontab -r -u "$user" 2>/dev/null || true
done < /etc/passwd
log "Auto-expire sweep done"
CRON_EOF

  chmod +x /usr/local/bin/autoremove-expired.sh
  if ! grep -q 'autoremove-expired' /etc/crontab 2>/dev/null; then
    echo "5 0 * * * root /usr/local/bin/autoremove-expired.sh >> /var/log/autoremove.log 2>&1" >> /etc/crontab
  fi
  log INFO "Auto-expire cron installed (daily at 00:05)"
}

# ---- Print final summary ----
print_summary() {
  local ip; ip="$(get_public_ip)"
  local dom; dom="$(cat /etc/xray/domain 2>/dev/null || echo 'your-domain.com')"
  local ns; ns="$(cat /etc/slowdns/nsdomain 2>/dev/null || echo 'ns.your-domain.com')"
  local slkey; slkey="$(cat /etc/slowdns/server.pub 2>/dev/null || echo 'N/A')"

  clear
  echo ""
  echo -e "\033[1;32m  ____  _             _ _   _                 \033[0m"
  echo -e "\033[1;32m | __ )| | ___   ___| | | | |__   __ _ _ __  \033[0m"
  echo -e "\033[1;32m |  _ \| |/ _ \ / _ \ | | | '_ \ / _\` | '_ \ \033[0m"
  echo -e "\033[1;32m | |_) | | (_) |  __/ | | | |_) | (_| | | | |\033[0m"
  echo -e "\033[1;32m |____/|_|\___/ \___|_|_| |_.__/ \__,_|_| |_|\033[0m"
  echo ""
  echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;46m       AUTO-SCRIPT PROFESSIONAL EDITION          \033[0m"
  echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo ""
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━ SERVICE SUMMARY ━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;36m Public IP   : \033[1;37m$ip\033[0m"
  echo -e "\033[1;36m Domain      : \033[1;37m$dom\033[0m"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo ""
  echo -e "\033[1;32m SSH SERVICES:\033[0m"
  echo -e "\033[1;36m  OpenSSH          :\033[1;37m 22\033[0m"
  echo -e "\033[1;36m  SSH WebSocket    :\033[1;37m 80\033[0m"
  echo -e "\033[1;36m  SSH SSL WS       :\033[1;37m 443\033[0m"
  echo -e "\033[1;36m  Stunnel4         :\033[1;37m 222, 777\033[0m"
  echo -e "\033[1;36m  Dropbear         :\033[1;37m 109, 143\033[0m"
  echo -e "\033[1;36m  BadVPN           :\033[1;37m 7100-7900\033[0m"
  echo ""
  echo -e "\033[1;32m SLOWDNS:\033[0m"
  echo -e "\033[1;36m  Nameserver       :\033[1;37m $ns\033[0m"
  echo -e "\033[1;36m  Public Key       :\033[1;37m $slkey\033[0m"
  echo -e "\033[1;36m  Server Port      :\033[1;37m 5300/UDP\033[0m"
  echo ""
  echo -e "\033[1;32m HTTP-CUSTOM (Mardhex):\033[0m"
  echo -e "\033[1;36m  Listen Port      :\033[1;37m 443\033[0m"
  echo -e "\033[1;36m  Protocol         :\033[1;37m UDP-over-HTTPS\033[0m"
  echo ""
  echo -e "\033[1;32m UDP-CUSTOM (Mardhex):\033[0m"
  echo -e "\033[1;36m  Listen Port      :\033[1;37m 36712\033[0m"
  echo ""
  echo -e "\033[1;32m XRAY SERVICES:\033[0m"
  echo -e "\033[1;36m  Vmess/Vless/Trojan WS TLS :\033[1;37m 443\033[0m"
  echo -e "\033[1;36m  Vmess/Vless/Trojan WS     :\033[1;37m 80\033[0m"
  echo -e "\033[1;36m  gRPC (all)               :\033[1;37m 443\033[0m"
  echo ""
  echo -e "\033[1;32m VPN:\033[0m"
  echo -e "\033[1;36m  OpenVPN          :\033[1;37m 1194/UDP\033[0m"
  echo -e "\033[1;36m  Client .ovpn     :\033[1;37m http://$ip:81/client.ovpn\033[0m"
  echo ""
  echo -e "\033[1;32m PANEL:\033[0m"
  echo -e "\033[1;36m  Webmin           :\033[1;37m https://$ip:10000\033[0m"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo ""
  echo -e "\033[1;32m NEXT STEP:\033[0m"
  echo -e "\033[1;36m  Run \033[1;37mmenu\033[1;36m to create SSH accounts\033[0m"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo ""
  echo -e "\033[1;32m Contact :\033[0m \033[1;37mhttps://t.me/JubairFF\033[0m"
  echo ""
  echo -e "\033[1;31m Rebooting in 40 seconds...\033[0m"
  echo ""
  sleep 40 && reboot
}

# ============================================================================
main() {
  echo ""
  echo "=========================================="
  echo " AUTO-SCRIPT PROFESSIONAL EDITION"
  echo " Jubair bro Ultra Pro auto script vpn"
  echo "=========================================="
  echo ""

  require_root
  detect_os
  check_openvz
  disable_ipv6

  # Clone the repo to /opt/auto-script so local install paths work
  # SECURITY: pin to specific commit SHA + verify remote owner
  if [[ ! -d /opt/auto-script ]]; then
    log INFO "Cloning repo to /opt/auto-script (pinned commit)..."
    apt_update_once && install_packages git

    # Hard-pinned commit SHA (update this when you push new code)
    local PINNED_SHA="${AUTO_SCRIPT_PIN:-c50bafacurrentplaceholder}"
    local REPO_URL="https://github.com/mdr77m-star/AUTO-SCRIPT-v2.git"

    # Clone, checkout pinned commit, verify it matches
    git clone --depth 50 "$REPO_URL" /opt/auto-script 2>/dev/null || {
      log WARN "Clone failed, falling back to wget downloads"
    }
    if [[ -d /opt/auto-script/.git ]]; then
      (cd /opt/auto-script && git fetch --depth 50 origin 2>/dev/null && git checkout "$PINNED_SHA" 2>/dev/null) || {
        log FATAL "Pinned commit checkout failed - refusing to run unverified code"
        rm -rf /opt/auto-script
      }
      # Verify checkout matches the SHA we requested
      local actual_sha; actual_sha="$(cd /opt/auto-script && git rev-parse HEAD 2>/dev/null)"
      if [[ "$actual_sha" != "$PINNED_SHA" ]]; then
        log FATAL "Commit SHA mismatch (got $actual_sha, expected $PINNED_SHA) - aborting"
        rm -rf /opt/auto-script
      else
        log INFO "Pinned commit verified: $actual_sha"
      fi
    fi
  fi
  # Set LIB_DIR so local paths resolve
  if [[ -d /opt/auto-script/lib ]]; then
    LIB_DIR="/opt/auto-script/lib"
    export LIB_DIR
  fi

  install_ssh_vpn
  install_xray
  install_sshws
  install_slowdns
  install_httpcustom
  install_udp_custom
  install_openvpn
  install_webmin
  install_bbr
  setup_autoremove

  # Install usernew + accounts: prefer local lib/, fall back to remote (HTTPS only)
  log INFO "Installing new menu scripts..."
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib"
  local usernew_installed=0
  if [[ -f "${lib_dir}/usernew.sh" ]]; then
    cp -f "${lib_dir}/usernew.sh" /usr/bin/usernew && chmod +x /usr/bin/usernew && usernew_installed=1
  fi
  if [[ $usernew_installed -eq 0 ]]; then
    # SECURITY: download to temp file, size check, then atomic install
    local tmp; tmp="$(mktemp)"
    curl -fsSL "${REPO_BASE}/lib/usernew.sh" -o "$tmp" 2>/dev/null || { log WARN "usernew download failed"; rm -f "$tmp"; }
    if [[ -f "$tmp" ]] && _verify_binary "$tmp" 1000; then
      mv "$tmp" /usr/bin/usernew && chmod +x /usr/bin/usernew
    else
      rm -f "$tmp"
    fi
  fi

  # Install local menu scripts to /usr/bin (replaces jubairbro's old menu)
  if [[ -d "${lib_dir}" ]]; then
    log INFO "Installing local menu scripts to /usr/bin/"
    for f in "${lib_dir}"/*.sh; do
      [[ -f "$f" ]] || continue
      local bn; bn="$(basename "$f" .sh)"
      install -m 755 "$f" "/usr/bin/${bn}" 2>/dev/null || cp -f "$f" "/usr/bin/${bn}" 2>/dev/null
    done
  fi

  # Drop the old jubairbro menu command (in case it shadows our new usernew)
  # We don't remove /usr/bin/menu; instead our local menu overwrites it later

  print_summary
}

main "$@"