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

ats_startup_process_matches() {
  if ! command -v pgrep >/dev/null 2>&1; then
    return 1
  fi

  pgrep -if '(^|[/\\[:space:]])(amtrucks\.exe|amtrucks)([[:space:]]|$)' >/dev/null 2>&1 \
    || pgrep -if "SteamLaunch[[:space:]].*AppId=${TRUCKNAV_ATS_APP_ID}" >/dev/null 2>&1 \
    || pgrep -if 'Proton[[:space:]].*waitforexitandrun.*amtrucks\.exe' >/dev/null 2>&1 \
    || pgrep -if 'waitforexitandrun.*amtrucks\.exe' >/dev/null 2>&1
}

ats_real_process_lines() {
  ps -eo pid=,comm=,args= | while read -r pid comm args; do
    [[ -n "${pid:-}" ]] || continue

    # Steam/Proton launch helpers can keep amtrucks.exe in their command line
    # after the actual game has exited. Never count them as the live game.
    if [[ "$args" =~ SteamLaunch[[:space:]].*AppId=${TRUCKNAV_ATS_APP_ID} ]] \
      || [[ "$args" =~ waitforexitandrun.*amtrucks\.exe ]]; then
      continue
    fi

    if [[ "$comm" =~ ^amtrucks(\.exe)?$ ]] \
      || [[ "$args" =~ (^|[/\\[:space:]])amtrucks(\.exe)?([[:space:]]|$) ]] \
      || [[ "$args" =~ [A-Za-z]:\\.*\\amtrucks\.exe([[:space:]]|$) ]]; then
      printf '%s %s\n' "$pid" "$args"
    fi
  done
}

ats_real_process_matches() {
  [[ -n "$(ats_real_process_lines | head -n 1)" ]]
}

wait_for_ats() {
  local detected=0
  for ((i = 1; i <= 180; i++)); do
    if ats_startup_process_matches; then
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
  local waiting_checks=0
  local real_process_line

  while true; do
    real_process_line="$(ats_real_process_lines | head -n 1)"
    if [[ -n "$real_process_line" ]]; then
      echo "ATS game process detected: $real_process_line"
      echo "Monitoring real ATS process"
      break
    fi

    waiting_checks=$((waiting_checks + 1))
    if ! ats_startup_process_matches; then
      missing_checks=$((missing_checks + 1))
      if ((missing_checks >= 6)); then
        echo "ATS process exited before the real game process was observed"
        echo "Stopping TruckNav"
        return 0
      fi
    else
      missing_checks=0
    fi

    if ((waiting_checks % 12 == 0)); then
      echo "Waiting for real ATS game process; ignoring Steam/Proton launcher wrappers"
    fi
    sleep 5
  done

  missing_checks=0
  while true; do
    if ats_real_process_matches; then
      missing_checks=0
    else
      missing_checks=$((missing_checks + 1))
      if ((missing_checks >= 3)); then
        echo "ATS process exited"
        echo "Stopping TruckNav"
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

  "$REPO_ROOT/scripts/linux/stop-trucknav.sh"
else
  echo "ATS was not detected after launching through Steam. TruckNav web app will keep running; use Stop TruckNav when finished."
fi
