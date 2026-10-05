#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

game="${1:-$TRUCKNAV_GAME}"
launch_started=$SECONDS

case "$game" in
  ats)
    game_label="ATS"
    app_id="$TRUCKNAV_ATS_APP_ID"
    game_exe="amtrucks.exe"
    ;;
  ets2)
    game_label="ETS2"
    app_id="$TRUCKNAV_ETS2_APP_ID"
    game_exe="eurotrucks2.exe"
    ;;
  *)
    echo "Usage: $0 ats|ets2" >&2
    exit 2
    ;;
esac

require_command node "Install Node.js with: sudo dnf install nodejs npm"
require_command npm "Install npm with: sudo dnf install npm"
require_command steam "Install Steam from Fedora/RPM Fusion or Flathub and ensure the steam command is available."
require_command protontricks-launch "Install protontricks with: sudo dnf install protontricks"

if [[ ! -f "$TELEMETRY_EXE" ]]; then
  echo "TruckNavTelemetry.exe was not found at: $TELEMETRY_EXE" >&2
  exit 1
fi

export TRUCKNAV_REPO_ROOT="$REPO_ROOT"
export TRUCKNAV_GAME="$game"

if [[ "$game" == "ets2" ]]; then
  if [[ ! -f "$REPO_ROOT/public/data/ets2/TRUCKNAV_TEST_BUILD.txt" \
     && ! -f "$REPO_ROOT/public/data/ets2/TRUCKNAV_BUNDLED_MAP.txt" ]]; then
    echo "Preparing bundled ETS2 map fallback..."
    bash "$REPO_ROOT/scripts/linux/prepare-ets2-bundled-map.sh"
  fi
fi

python3 "$REPO_ROOT/scripts/linux/set-shared-game.py" "$game"

# Keep this before game launch so the plugin DLL is already present when the
# game loads it. Game-directory lookup is fast and uses Steam library metadata.
bash "$REPO_ROOT/scripts/linux/install-game-telemetry-plugin.sh" "$game"

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

game_startup_process_matches() {
  if ! command -v pgrep >/dev/null 2>&1; then
    return 1
  fi

  pgrep -if "$game_exe" >/dev/null 2>&1 \
    || pgrep -if "SteamLaunch[[:space:]].*AppId=${app_id}" >/dev/null 2>&1
}

game_real_process_lines() {
  local lower_exe="${game_exe,,}"

  ps -eo pid=,comm=,args= | while read -r pid comm args; do
    [[ -n "${pid:-}" ]] || continue

    local lower_comm="${comm,,}"
    local lower_args="${args,,}"

    if [[ "$lower_args" == *"steamlaunch"*"appid=${app_id}"* ]] \
      || [[ "$lower_args" == *"waitforexitandrun"*"$lower_exe"* ]]; then
      continue
    fi

    if [[ "$lower_comm" == "$lower_exe" ]] \
      || [[ "$lower_comm" == "${lower_exe%.exe}" ]] \
      || [[ "$lower_args" == *"$lower_exe"* ]]; then
      printf '%s %s\n' "$pid" "$args"
    fi
  done
}

game_real_process_matches() {
  local matches
  matches="$(game_real_process_lines)"
  [[ -n "$matches" ]]
}

wait_for_telemetry_port() {
  for ((i = 1; i <= 80; i++)); do
    if telemetry_port_open; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

stop_telemetry_helper() {
  local telemetry_pid
  telemetry_pid="$(pid_from_file "$TELEMETRY_PID_FILE")"

  if is_pid_running "$telemetry_pid"; then
    kill "$telemetry_pid" 2>/dev/null || true
    for ((i = 1; i <= 20; i++)); do
      is_pid_running "$telemetry_pid" || break
      sleep 0.1
    done
  fi

  pkill -f "TruckNavTelemetry.exe" 2>/dev/null || true

  for ((i = 1; i <= 20; i++)); do
    telemetry_port_open || break
    sleep 0.1
  done

  rm -f "$TELEMETRY_PID_FILE" "$TELEMETRY_GAME_FILE"
}

start_telemetry() {
  local telemetry_pid current_game=""
  telemetry_pid="$(pid_from_file "$TELEMETRY_PID_FILE")"
  [[ -f "$TELEMETRY_GAME_FILE" ]] && current_game="$(cat "$TELEMETRY_GAME_FILE" 2>/dev/null || true)"

  # Fast path: if the right helper already owns the socket, there is nothing
  # useful to restart.
  if [[ "$current_game" == "$game" ]] && telemetry_port_open; then
    echo "Telemetry bridge is already listening for $game_label on port 30001."
    return
  fi

  if is_pid_running "$telemetry_pid" || telemetry_port_open; then
    if [[ "$current_game" == "$game" ]]; then
      echo "Restarting stale $game_label telemetry helper..."
    else
      echo "Switching telemetry from ${current_game:-unknown} to $game_label..."
    fi
    stop_telemetry_helper
  fi

  echo "Starting telemetry for $game_label with protontricks app id $app_id..."
  protontricks-launch --appid "$app_id" "$TELEMETRY_EXE" >"$PID_DIR/telemetry.log" 2>&1 &
  echo "$!" > "$TELEMETRY_PID_FILE"
  printf '%s\n' "$game" > "$TELEMETRY_GAME_FILE"

  if wait_for_telemetry_port; then
    echo "Telemetry bridge is listening on port 30001."
  else
    echo "Telemetry bridge did not open port 30001." >&2
    echo "Last telemetry log lines:" >&2
    tail -n 20 "$PID_DIR/telemetry.log" >&2 || true
    return 1
  fi
}

monitor_game() {
  local missing_checks=0
  local waiting_checks=0
  local real_process_lines_output=""
  local real_process_line=""

  while true; do
    real_process_lines_output="$(game_real_process_lines)"
    real_process_line="${real_process_lines_output%%$'\n'*}"

    if [[ -n "$real_process_line" ]]; then
      echo "$game_label game process detected: $real_process_line"
      echo "Monitoring real $game_label process"
      break
    fi

    waiting_checks=$((waiting_checks + 1))
    if ! game_startup_process_matches; then
      missing_checks=$((missing_checks + 1))
      if ((missing_checks >= 60)); then
        echo "$game_label process was not detected."
        echo "TruckNav will keep running; use Stop TruckNav when finished."
        return 0
      fi
    else
      missing_checks=0
    fi

    if ((waiting_checks % 10 == 0)); then
      echo "Waiting for real $game_label game process..."
    fi
    sleep 1
  done

  missing_checks=0
  while true; do
    if game_real_process_matches; then
      missing_checks=0
    else
      missing_checks=$((missing_checks + 1))
      if ((missing_checks >= 3)); then
        echo "$game_label process exited"
        echo "Stopping TruckNav"
        return 0
      fi
    fi
    sleep 2
  done
}

echo "Starting TruckNav web app"
start_web_app

if game_real_process_matches; then
  echo "$game_label is already running; leaving the game open."
elif game_startup_process_matches; then
  echo "$game_label is already starting; not launching a second copy."
else
  echo "Launching $game_label"
  steam "steam://rungameid/$app_id" >/dev/null 2>&1 &
fi

# The telemetry helper is a listener and does not need the game to be fully
# booted first. Start it immediately so game startup and Proton helper startup
# overlap instead of adding fixed delays.
echo "Starting telemetry"
start_telemetry
echo "TruckNav telemetry ready in $((SECONDS - launch_started))s."

echo "Monitoring $game_label"
monitor_game

# Preserve the original combined-launch behavior: once the game exits, stop
# TruckNav web + telemetry. This never stops Steam or the game itself.
"$REPO_ROOT/scripts/linux/stop-trucknav.sh"
