#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command node "Install Node.js with: sudo dnf install nodejs npm"
require_command npm "Install npm with: sudo dnf install npm"
require_command protontricks-launch "Install protontricks with: sudo dnf install protontricks"

if [[ ! -f "$TELEMETRY_EXE" ]]; then
  echo "TruckNavTelemetry.exe was not found at: $TELEMETRY_EXE" >&2
  exit 1
fi

cd "$REPO_ROOT"

web_pid="$(pid_from_file "$WEB_PID_FILE")"
if is_pid_running "$web_pid"; then
  echo "TruckNav web app is already running (PID $web_pid)."
else
  echo "Starting TruckNav web app from $REPO_ROOT..."
  npm run dev -- --host 0.0.0.0 >"$PID_DIR/web.log" 2>&1 &
  echo "$!" > "$WEB_PID_FILE"
fi

telemetry_pid="$(pid_from_file "$TELEMETRY_PID_FILE")"
if is_pid_running "$telemetry_pid"; then
  echo "TruckNav telemetry helper is already running (PID $telemetry_pid)."
else
  echo "Starting TruckNav telemetry helper with protontricks app id $TRUCKNAV_ATS_APP_ID..."
  protontricks-launch --appid "$TRUCKNAV_ATS_APP_ID" "$TELEMETRY_EXE" >"$PID_DIR/telemetry.log" 2>&1 &
  echo "$!" > "$TELEMETRY_PID_FILE"
fi

echo "TruckNav is starting. Open $TRUCKNAV_URL"

if [[ "${1:-}" == "--wait" ]]; then
  cleanup() {
    "$REPO_ROOT/scripts/linux/stop-trucknav.sh" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT INT TERM
  echo "Keeping TruckNav attached to this terminal. Close this terminal or press Ctrl+C to stop TruckNav."
  while true; do
    active=0
    web_pid="$(pid_from_file "$WEB_PID_FILE")"
    telemetry_pid="$(pid_from_file "$TELEMETRY_PID_FILE")"
    is_pid_running "$web_pid" && active=1
    is_pid_running "$telemetry_pid" && active=1
    [[ "$active" == "1" ]] || break
    sleep 2
  done
fi
