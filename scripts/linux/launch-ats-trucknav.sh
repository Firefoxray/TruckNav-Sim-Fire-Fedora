#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command node "Install Node.js with: sudo dnf install nodejs npm"
require_command npm "Install npm with: sudo dnf install npm"
require_command steam "Install Steam from Fedora/RPM Fusion or Flathub and ensure the steam command is available."
require_command protontricks-launch "Install protontricks with: sudo dnf install protontricks"

if [[ ! -f "$TELEMETRY_EXE" ]]; then
  echo "TruckNavTelemetry.exe was not found at: $TELEMETRY_EXE" >&2
  exit 1
fi

start_web_app() {
  cd "$REPO_ROOT"

  local web_pid
  web_pid="$(pid_from_file "$WEB_PID_FILE")"
  if is_pid_running "$web_pid"; then
    echo "TruckNav web app is already running (PID $web_pid)."
    return
  fi

  rm -f "$WEB_PID_FILE"
  echo "Starting TruckNav web app from $REPO_ROOT..."
  npm run dev -- --host 0.0.0.0 >"$PID_DIR/web.log" 2>&1 &
  echo "$!" > "$WEB_PID_FILE"
  echo "TruckNav web app is starting. Open $TRUCKNAV_URL"
}

ats_process_matches() {
  if ! command -v pgrep >/dev/null 2>&1; then
    return 1
  fi

  pgrep -if '(^|/)(amtrucks\.exe|amtrucks)([[:space:]]|$)' >/dev/null 2>&1 \
    || pgrep -if 'SteamLaunch[[:space:]].*AppId=270880' >/dev/null 2>&1 \
    || pgrep -if 'Proton[[:space:]].*waitforexitandrun.*amtrucks\.exe' >/dev/null 2>&1 \
    || pgrep -if 'waitforexitandrun.*amtrucks\.exe' >/dev/null 2>&1
}

wait_for_ats() {
  local detected=0
  for ((i = 1; i <= 180; i++)); do
    if ats_process_matches; then
      detected=1
      break
    fi
    sleep 2
  done

  [[ "$detected" == "1" ]]
}

start_telemetry() {
  local telemetry_pid
  telemetry_pid="$(pid_from_file "$TELEMETRY_PID_FILE")"
  if is_pid_running "$telemetry_pid"; then
    echo "TruckNav telemetry helper is already running (PID $telemetry_pid)."
    return
  fi

  rm -f "$TELEMETRY_PID_FILE"
  echo "Starting telemetry with protontricks app id $TRUCKNAV_ATS_APP_ID..."
  protontricks-launch --appid "$TRUCKNAV_ATS_APP_ID" "$TELEMETRY_EXE" >"$PID_DIR/telemetry.log" 2>&1 &
  echo "$!" > "$TELEMETRY_PID_FILE"
}

monitor_ats() {
  local missing_checks=0

  while true; do
    if ats_process_matches; then
      missing_checks=0
    else
      missing_checks=$((missing_checks + 1))
      if ((missing_checks >= 6)); then
        return 0
      fi
    fi
    sleep 5
  done
}

echo "Starting TruckNav web app"
start_web_app

echo "Launching ATS"
steam "steam://rungameid/$TRUCKNAV_ATS_APP_ID" >/dev/null 2>&1 &

echo "Waiting for ATS"
if wait_for_ats; then
  echo "ATS detected. Waiting briefly before telemetry starts..."
  sleep 15

  echo "Starting telemetry"
  start_telemetry

  echo "Monitoring ATS"
  monitor_ats

  echo "ATS closed, stopping TruckNav"
  "$REPO_ROOT/scripts/linux/stop-trucknav.sh"
else
  echo "ATS was not detected after launching through Steam. TruckNav web app will keep running; use Stop TruckNav when finished."
fi
