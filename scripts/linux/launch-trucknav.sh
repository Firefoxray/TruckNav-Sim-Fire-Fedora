#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

game="$TRUCKNAV_GAME"
wait_mode=0

for arg in "$@"; do
  case "$arg" in
    ats|ets2)
      game="$arg"
      ;;
    --wait)
      wait_mode=1
      ;;
    *)
      echo "Usage: $0 [ats|ets2] [--wait]" >&2
      exit 2
      ;;
  esac
done

case "$game" in
  ats)
    game_label="ATS"
    app_id="$TRUCKNAV_ATS_APP_ID"
    ;;
  ets2)
    game_label="ETS2"
    app_id="$TRUCKNAV_ETS2_APP_ID"
    ;;
  *)
    echo "Unknown game: $game" >&2
    exit 2
    ;;
esac

require_command node "Install Node.js with: sudo dnf install nodejs npm"
require_command npm "Install npm with: sudo dnf install npm"
require_command protontricks-launch "Install protontricks with: sudo dnf install protontricks"

if [[ ! -f "$TELEMETRY_EXE" ]]; then
  echo "TruckNavTelemetry.exe was not found at: $TELEMETRY_EXE" >&2
  exit 1
fi

cd "$REPO_ROOT"
export TRUCKNAV_REPO_ROOT="$REPO_ROOT"
export TRUCKNAV_GAME="$game"

if [[ "$game" == "ets2" && ! -f "$REPO_ROOT/public/data/ets2/TRUCKNAV_BUNDLED_MAP.txt" ]]; then
  echo "Preparing bundled ETS2 map..."
  bash "$REPO_ROOT/scripts/linux/prepare-ets2-bundled-map.sh"
fi

python3 "$REPO_ROOT/scripts/linux/set-shared-game.py" "$game"
bash "$REPO_ROOT/scripts/linux/install-game-telemetry-plugin.sh" "$game"

web_pid="$(pid_from_file "$WEB_PID_FILE")"
if is_pid_running "$web_pid"; then
  echo "TruckNav web app is already running (PID $web_pid)."
else
  echo "Starting TruckNav web app from $REPO_ROOT..."
  npm run dev -- --host 0.0.0.0 >"$PID_DIR/web.log" 2>&1 &
  echo "$!" > "$WEB_PID_FILE"
fi

wait_for_telemetry_port() {
  for ((i = 1; i <= 40; i++)); do
    if ss -lnt 2>/dev/null | grep -Eq '[:.]30001[[:space:]]'; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

telemetry_pid="$(pid_from_file "$TELEMETRY_PID_FILE")"
current_game=""
[[ -f "$TELEMETRY_GAME_FILE" ]] && current_game="$(cat "$TELEMETRY_GAME_FILE" 2>/dev/null || true)"

if is_pid_running "$telemetry_pid" && [[ "$current_game" != "$game" ]]; then
  echo "Switching telemetry from ${current_game:-unknown} to $game_label..."
  kill "$telemetry_pid" 2>/dev/null || true
  sleep 2
  rm -f "$TELEMETRY_PID_FILE" "$TELEMETRY_GAME_FILE"
  pkill -f "TruckNavTelemetry.exe" 2>/dev/null || true
  telemetry_pid=""
fi

if is_pid_running "$telemetry_pid" && [[ "$current_game" == "$game" ]]; then
  echo "TruckNav telemetry helper is already running for $game_label (PID $telemetry_pid)."
else
  echo "Starting TruckNav telemetry helper for $game_label with protontricks app id $app_id..."
  protontricks-launch --appid "$app_id" "$TELEMETRY_EXE" >"$PID_DIR/telemetry.log" 2>&1 &
  echo "$!" > "$TELEMETRY_PID_FILE"
  printf '%s\n' "$game" > "$TELEMETRY_GAME_FILE"

  if wait_for_telemetry_port; then
    echo "Telemetry bridge is listening on port 30001."
  else
    echo "Telemetry bridge did not open port 30001." >&2
    echo "Last telemetry log lines:" >&2
    tail -n 20 "$PID_DIR/telemetry.log" >&2 || true
    exit 1
  fi
fi

echo "TruckNav is starting for $game_label. Open $TRUCKNAV_URL"

if [[ "$wait_mode" == "1" ]]; then
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
