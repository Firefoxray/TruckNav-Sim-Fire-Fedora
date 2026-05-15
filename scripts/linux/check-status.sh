#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

status_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "OK: $cmd ($(command -v "$cmd"))"
  else
    echo "MISSING: $cmd"
  fi
}

status_pid() {
  local label="$1"
  local file="$2"
  local pid
  pid="$(pid_from_file "$file")"
  if is_pid_running "$pid"; then
    echo "RUNNING: $label (PID $pid)"
  else
    echo "STOPPED: $label"
  fi
}

echo "TruckNav repository: $REPO_ROOT"
echo "ATS Steam app id: $TRUCKNAV_ATS_APP_ID"
echo "TruckNav URL: $TRUCKNAV_URL"
echo
status_command node
status_command npm
status_command protontricks-launch
status_command steam
status_command python3
if python3 - <<'PY' >/dev/null 2>&1
import tkinter
PY
then
  echo "OK: python3 tkinter"
else
  echo "MISSING: python3 tkinter (install python3-tkinter on Fedora)"
fi

echo
if [[ -f "$TELEMETRY_EXE" ]]; then
  echo "OK: telemetry helper found at $TELEMETRY_EXE"
else
  echo "MISSING: telemetry helper not found at $TELEMETRY_EXE"
fi
[[ -d "$REPO_ROOT/node_modules" ]] && echo "OK: npm dependencies installed" || echo "MISSING: node_modules (run npm install)"

echo
status_pid "TruckNav web app" "$WEB_PID_FILE"
status_pid "TruckNav telemetry helper" "$TELEMETRY_PID_FILE"
