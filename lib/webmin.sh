#!/usr/bin/env bash
# Webmin module - real Webmin panel + ADS block list.
set -euo pipefail
source /c/Users/IK/Desktop/AUTO-SCRIPT-master/lib/common.sh

install_webmin() {
  log "INFO" "=== Installing Webmin ==="

  apt_update_once
  install_packages wget apt-transport-https gnupg curl

  if ! grep -q 'webmin' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    wget -qO- http://www.webmin.com/jcameron-key.asc 2>/dev/null | apt-key add - 2>/dev/null || true
    echo "deb http://download.webmin.com/apt webmain main" > /etc/apt/sources.list.d/webmin.list
    apt-get update -y 2>/dev/null
  fi

  apt-get install -y webmin 2>/dev/null || {
    log "WARN" "Webmin apt install failed"
  }

  systemctl restart webmin 2>/dev/null || true
  systemctl enable webmin 2>/dev/null || true

  if wait_port 10000 "webmin" 15; then
    log "INFO" "Webmin UP on :10000"
  else
    log "WARN" "Webmin port 10000 not confirmed"
  fi
}