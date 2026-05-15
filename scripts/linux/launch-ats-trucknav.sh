#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command steam "Install Steam from Fedora/RPM Fusion or Flathub and ensure the steam command is available."

"$REPO_ROOT/scripts/linux/launch-trucknav.sh"

echo "Launching American Truck Simulator through Steam app id $TRUCKNAV_ATS_APP_ID..."
steam "steam://rungameid/$TRUCKNAV_ATS_APP_ID" >/dev/null 2>&1 &

if command -v pgrep >/dev/null 2>&1; then
  echo "Waiting for ATS process to appear so TruckNav can stop after ATS exits if detectable..."
  detected=0
  for ((i = 1; i <= 120; i++)); do
    if pgrep -if '(^|/)(amtrucks|American Truck Simulator)(\.exe)?' >/dev/null 2>&1; then
      detected=1
      break
    fi
    sleep 2
  done

  if [[ "$detected" == "1" ]]; then
    echo "ATS detected. TruckNav will stop after ATS exits."
    while pgrep -if '(^|/)(amtrucks|American Truck Simulator)(\.exe)?' >/dev/null 2>&1; do
      sleep 5
    done
    echo "ATS exited; stopping TruckNav."
    "$REPO_ROOT/scripts/linux/stop-trucknav.sh"
  else
    echo "ATS process was not detectable. TruckNav will keep running; use Stop TruckNav when finished."
  fi
fi
