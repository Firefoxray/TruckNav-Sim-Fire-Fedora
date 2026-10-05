#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command node "Install Node.js with: sudo dnf install nodejs npm"
require_command npm "Install npm with: sudo dnf install npm"

cd "$REPO_ROOT"
export TRUCKNAV_REPO_ROOT="$REPO_ROOT"

web_pid="$(pid_from_file "$WEB_PID_FILE")"
if is_pid_running "$web_pid"; then
  echo "TruckNav web app is already running (PID $web_pid)."
else
  rm -f "$WEB_PID_FILE"
  echo "Starting TruckNav UI only from $REPO_ROOT..."
  npm run dev -- --host 0.0.0.0 >"$PID_DIR/web.log" 2>&1 &
  echo "$!" > "$WEB_PID_FILE"
fi

echo "No ATS/ETS2 process was launched."
echo "No telemetry helper was started."
echo "Open $TRUCKNAV_URL"
