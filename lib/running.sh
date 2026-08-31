#!/usr/bin/env bash
# Service status display - lists all managed services
set -euo pipefail
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

check() {
  local svc="$1" label="$2"
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo -e "  ${GREEN}[ON]${NC}  $label ($svc)"
  else
    echo -e "  ${RED}[OFF]${NC} $label ($svc)"
  fi
}

echo -e "${YELLOW}=== Service Status ===${NC}"
check ssh          "OpenSSH"
check dropbear     "Dropbear"
check stunnel4     "Stunnel4"
check nginx        "Nginx"
check xray         "Xray"
check sshws        "SSH WebSocket"
check server-sldns "SlowDNS Server"
check client-sldns "SlowDNS Client"
check http-custom  "HTTP-Custom"
check udp-custom   "UDP-Custom"
check openvpn@server "OpenVPN"
check webmin       "Webmin"
echo ""
echo "Press any key..."
read -n 1 -s -r