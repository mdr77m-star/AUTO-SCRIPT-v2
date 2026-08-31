#!/usr/bin/env bash
# ============================================================================
#  Account store — persistent, JSON-backed SSH / proxy account ledger.
#  Every account creation writes here; cron job expires old ones; setup prints
#  a clean summary at the end.  Replaces the old scattered /etc/log-create-ssh.log.
# ============================================================================
set -euo pipefail

readonly ACCOUNTS_FILE="${ACCOUNTS_FILE:-/root/accounts.json}"
readonly ACCOUNTS_LOG="${ACCOUNTS_LOG:-/root/accounts.log}"

# ---- low-level JSON helpers (no jq dependency) --------------------------------
json_escape() {
  printf '%s' "$1" | sed -e 's/\/\\/g' -e 's/"/\\"/g' -e 's/\t/\t/g'
}

accounts_init() {
  if [[ ! -f "$ACCOUNTS_FILE" ]]; then
    echo '[]' > "$ACCOUNTS_FILE"
  fi
}

# args: id, username, password, expires, protocol, host, port, path, extra
account_add() {
  local id="${1:?}" user="${2:?}" pass="${3:?}" expires="${4:?}"
  local proto="${5:-SSH}" host="${6:-}" port="${7:-}" path="${8:-}" extra="${9:-}"
  accounts_init

  local now; now="$(date +%s)"
  local exp_ts; exp_ts="$(date -d "$expires" +%s 2>/dev/null || echo 0)"
  local row
  row="$(cat <<JSON
{"id":"$(json_escape "$id")","username":"$(json_escape "$user")","password":"$(json_escape "$pass")","expires":"$(json_escape "$expires")","exp_ts":$exp_ts,"protocol":"$(json_escape "$proto")","host":"$(json_escape "$host")","port":"$(json_escape "$port")","path":"$(json_escape "$path")","extra":"$(json_escape "$extra")","created":$now}
JSON
)"
  # append object to array (jq-free)
  if grep -q '^\[\]$' "$ACCOUNTS_FILE"; then
    sed -i 's/^\[\]$//' "$ACCOUNTS_FILE"
  else
    sed -i 's/^\[\(.*\)\]$/\1/' "$ACCOUNTS_FILE"
  fi
  if [[ -s "$ACCOUNTS_FILE" ]]; then
    printf ',' >> "$ACCOUNTS_FILE"
  fi
  printf '%s' "$row" >> "$ACCOUNTS_FILE"
  printf ']' >> "$ACCOUNTS_FILE"

  log_account "$user" "$pass" "$expires" "$proto" "$host" "$port" "$path" "$extra"
}

log_account() {
  {
    echo "=================================================================="
    echo "Account created: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Username : $1"
    echo "Password : $2"
    echo "Expires  : $3"
    echo "Protocol : $4"
    echo "Host     : $5"
    echo "Port     : $6"
    echo "Path     : $7"
    echo "Extra    : $8"
    echo "=================================================================="
  } | tee -a "$ACCOUNTS_LOG"
}

# ---- expiry sweep (jq-free, awk-based) --------------------------------------
account_expire() {
  accounts_init
  local now; now="$(date +%s)"
  local tmp; tmp="$(mktemp)"
  awk -v now="$now" '
    BEGIN { first=1 }
    {
      line=$0
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (line == "" || line == "[]" || line == "[") next
      if (line == "]") next
      gsub(/^,/, "", line)
      if (line !~ /"exp_ts"/) next
      exp=0
      if (match(line, /"exp_ts":([0-9]+)/, a)) exp=a[1]
      if (exp > 0 && exp < now) {
        # expired -> drop
        next
      }
      if (first) first=0; else printf ","
      printf "%s", line
    }
  ' "$ACCOUNTS_FILE" > "$tmp"
  printf ']' >> "$tmp"
  mv "$tmp" "$ACCOUNTS_FILE"
}

# ---- summary printer ---------------------------------------------------------
account_summary() {
  accounts_init
  echo ""
  log "INFO" "================  ACCOUNT SUMMARY  ================"
  if ! grep -q '"exp_ts"' "$ACCOUNTS_FILE"; then
    log "INFO" "(no accounts yet)"
    log "INFO" "===================================================="
    return 0
  fi
  awk '
    {
      line=$0
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (line == "" || line == "[]" || line == "[" || line == "]") next
      gsub(/^,/, "", line)
      printf "%s\n", line
    }
  ' "$ACCOUNTS_FILE" | tr ',' '\n' | while IFS= read -r obj; do
    obj="$(echo "$obj" | sed 's/^[ \t]*//;s/[ \t]*$//')"
    [[ -z "$obj" ]] && continue
    user="$(echo "$obj" | sed -n 's/.*"username":"\([^"]*\)".*/\1/p')"
    pass="$(echo "$obj" | sed -n 's/.*"password":"\([^"]*\)".*/\1/p')"
    exp="$(echo "$obj" | sed -n 's/.*"expires":"\([^"]*\)".*/\1/p')"
    proto="$(echo "$obj" | sed -n 's/.*"protocol":"\([^"]*\)".*/\1/p')"
    host="$(echo "$obj" | sed -n 's/.*"host":"\([^"]*\)".*/\1/p')"
    port="$(echo "$obj" | sed -n 's/.*"port":"\([^"]*\)".*/\1/p')"
    path="$(echo "$obj" | sed -n 's/.*"path":"\([^"]*\)".*/\1/p')"
    log "INFO" "  ${proto} | ${user}:${pass} | ${host}:${port} | exp ${exp} | path ${path}"
  done
  log "INFO" "===================================================="
}

# ---- account list (used by menu) --------------------------------------------
account_list() {
  accounts_init
  awk '{ gsub(/^[ \t]+|[ \t]+$/,""); if ($0==""||$0=="[]"||$0=="["||$0=="]") next; gsub(/^,/,""); print }' "$ACCOUNTS_FILE" \
    | tr ',' '\n' | sed 's/^[ \t]*//;s/[ \t]*$//' | grep -v '^$'
}
