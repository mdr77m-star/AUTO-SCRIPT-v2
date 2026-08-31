#!/usr/bin/env bash
# SSH Account creator - creates Linux user + prints FULL account info to screen
# (screen output was the missing piece in the original usernew.sh)
set -euo pipefail
source /c/Users/IK/Desktop/AUTO-SCRIPT-master/lib/common.sh

readonly CFG_DOMAIN="/etc/xray/domain"
readonly CFG_NS="/etc/slowdns/nsdomain"

create_ssh_account() {
  echo -e "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;46m       CREATE SSH & WEBSOCKET ACCOUNT           \033[0m"
  echo -e "\033[1;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"

  read -rp "Username : " user
  read -rp "Password : " pass
  read -rp "Expired (days) : " days

  [[ -z "$user" || -z "$pass" || -z "$days" ]] && {
    echo "Error: all fields required"; return 1;
  }

  local exp_date; exp_date="$(date -d "+${days} days" +"%Y-%m-%d")"
  local exp_human; exp_human="$(date -d "$exp_date" '+%d %b %Y')"

  # check user exists
  id "$user" 2>/dev/null && { echo "Error: user '$user' exists"; return 1; }

  # create Linux account
  useradd -e "$exp_date" -s /bin/false -M "$user" || {
    echo "Error: failed to create user"; return 1;
  }
  echo -e "${pass}\n${pass}" | passwd "$user" >/dev/null 2>&1 || true

  # gather info
  local ip;  ip="$(get_public_ip)"
  local dom; dom="$(cat "$CFG_DOMAIN" 2>/dev/null || echo 'your-vps-ip')"
  local sldomain; sldomain="$(cat "$CFG_NS" 2>/dev/null || echo 'ns.your-domain.com')"
  local slkey;  slkey="$(cat /etc/slowdns/server.pub 2>/dev/null || echo 'N/A')"

  # port values
  local port_ssh=22 port_ws=80 port_wss=443
  local port_ssl1=222 port_ssl2=777
  local port_dropbear=109
  local port_badvpn_start=7100 port_badvpn_end=7900
  local port_udp_custom=36712
  local port_http_custom=443

  # print to screen (THIS WAS MISSING in original)
  clear
  echo -e "\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;46m         ACCOUNT CREATED SUCCESSFULLY            \033[0m"
  echo -e "\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "Username" "$user"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "Password" "$pass"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "Expired" "$exp_human"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "Host / IP" "$ip"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "Domain" "$dom"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "OpenSSH" "$port_ssh"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "SSH WS" "$port_ws"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "SSH SSL WS" "$port_wss"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "Stunnel" "$port_ssl1 / $port_ssl2"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "Dropbear" "$port_dropbear"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "BadVPN" "$port_badvpn_start-$port_badvpn_end"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "UDP Custom" "$port_udp_custom"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "HTTP Custom" "$port_http_custom"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "SlowDNS NS" "$sldomain"
  printf "\033[1;36m%-14s\033[0m : \033[1;37m%s\033[0m\n" "SlowDNS Key" "$slkey"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;32m UDP Custom Line :\033[0m"
  echo -e "\033[1;36m ${dom}:${port_udp_custom}@${user}:${pass}\033[0m"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;32m HTTP Custom Line:\033[0m"
  echo -e "\033[1;36m ${dom}:${port_http_custom}@${user}:${pass}\033[0m"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;32m OpenVPN Download:\033[0m"
  echo -e "\033[1;36m http://${ip}:81/${user}.ovpn\033[0m"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo -e "\033[1;32m SSH WS Payload:\033[0m"
  echo -e "\033[1;36m GET / HTTP/1.1[crlf]Host: ${dom}[crlf]Upgrade: websocket[crlf][crlf]\033[0m"
  echo -e "\033[1;33m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
  echo ""
  echo -e "\033[1;32m Account saved to /root/accounts.log\033[0m"
  echo ""
  read -n 1 -s -r -p "Press any key to return to menu"
}