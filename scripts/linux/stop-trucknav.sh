#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

stop_pid_file() {
  local name="$1"
  local file="$2"
  local pid
  pid="$(pid_from_file "$file")"
  if is_pid_running "$pid"; then
    echo "Stopping $name (PID $pid)..."
    kill "$pid" 2>/dev/null || true
    sleep 2
    if is_pid_running "$pid"; then
      echo "Forcing $name to stop..."
      kill -TERM "$pid" 2>/dev/null || true
    fi
  else
    echo "$name is not running from the saved PID file."
  fi
  rm -f "$file"
}

stop_pid_file "TruckNav telemetry helper" "$TELEMETRY_PID_FILE"
stop_pid_file "TruckNav web app" "$WEB_PID_FILE"

pkill -f "protontricks-launch --appid ${TRUCKNAV_ATS_APP_ID} .*TruckNavTelemetry.exe" 2>/dev/null || true
pkill -f "TruckNavTelemetry.exe" 2>/dev/null || true

echo "TruckNav stop request complete."
