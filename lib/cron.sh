#!/usr/bin/env bash
# Cron module - auto-expire SSH accounts (runs daily).
set -euo pipefail
source /c/Users/IK/Desktop/AUTO-SCRIPT-master/lib/common.sh

setup_cron_autoremove() {
  log "INFO" "=== Setting up cron auto-remove expired accounts ==="

  cat > /usr/local/bin/autoremove-expired.sh <<'CRON_EOF'
#!/usr/bin/env bash
# Auto-remove expired Linux accounts (runs daily via cron at 00:05)
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

  log "INFO" "Auto-expire cron installed (daily at 00:05)"
}