#!/usr/bin/env bash
# Menu - main VPS management script (replaces jubairbro's menu).
# Sources all module functions from /usr/bin/ and provides an interactive shell.
set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

header() {
  clear
  local domain; domain="$(cat /etc/xray/domain 2>/dev/null || echo 'your-domain.com')"
  local ip; ip="$(curl -fsS -m 5 ifconfig.me 2>/dev/null || echo unknown)"
  echo -e "${CYAN}========================================${NC}"
  echo -e "${GREEN}     AUTO-SCRIPT PROFESSIONAL MENU${NC}"
  echo -e "${CYAN}========================================${NC}"
  echo -e "  ${YELLOW}Domain :${NC} $domain"
  echo -e "  ${YELLOW}IP     :${NC} $ip"
  echo -e "${CYAN}========================================${NC}"
}

show_menu() {
  header
  echo ""
  echo -e "  ${GREEN}1${NC}  - Create SSH Account"
  echo -e "  ${GREEN}2${NC}  - List SSH Accounts"
  echo -e "  ${GREEN}3${NC}  - Delete SSH Account"
  echo -e "  ${GREEN}4${NC}  - Renew SSH Account"
  echo -e "  ${GREEN}5${NC}  - View Connection Info (SlowDNS/HTTP-Custom)"
  echo -e "  ${GREEN}6${NC}  - Service Status"
  echo -e "  ${GREEN}7${NC}  - Reboot VPS"
  echo -e "  ${GREEN}x${NC}  - Exit"
  echo ""
  read -rp "Select: " opt
  case "$opt" in
    1) usernew ;;
    2) bash /usr/bin/accounts.sh summary 2>/dev/null || { echo "(no accounts)"; sleep 2; }; ;;
    3) read -rp "Username to delete: " u
       # SECURITY: validate username matches POSIX safe pattern
       if [[ "$u" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
         userdel -rf "$u" 2>/dev/null && echo "Deleted: $u" || echo "Not found"
       else
         echo "Invalid username"
       fi
       sleep 2 ;;
    4) read -rp "Username to renew: " u
       read -rp "Days to add: " d
       # SECURITY: validate inputs strictly
       if [[ "$u" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [[ "$d" =~ ^[0-9]+$ ]]; then
         local exp_date; exp_date="$(date -d "+${d} days" +%Y-%m-%d)"
         chage -E "$exp_date" "$u" 2>/dev/null && echo "Renewed: $u (+$d days)" || echo "Failed"
       else
         echo "Invalid username or days"
       fi
       sleep 2 ;;
    5) bash /usr/bin/usernew --info 2>/dev/null || echo "Run: usernew (no args) to create, or check /etc/slowdns/server.pub"; sleep 3; ;;
    6) bash /usr/bin/running 2>/dev/null || { echo "Services:"; systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -20; }; ;;
    7) echo "Rebooting..."; sleep 2; /sbin/reboot; ;;
    x) exit 0 ;;
    *) echo "Invalid"; sleep 1; ;;
  esac
}

while true; do show_menu; done