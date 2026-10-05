#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

game="${1:-$TRUCKNAV_GAME}"

case "$game" in
  ats)
    app_id="$TRUCKNAV_ATS_APP_ID"
    game_dir_name="American Truck Simulator"
    game_label="ATS"
    env_dir_var="TRUCKNAV_ATS_DIR"
    ;;
  ets2)
    app_id="$TRUCKNAV_ETS2_APP_ID"
    game_dir_name="Euro Truck Simulator 2"
    game_label="ETS2"
    env_dir_var="TRUCKNAV_ETS2_DIR"
    ;;
  *)
    echo "Usage: $0 ats|ets2" >&2
    exit 2
    ;;
esac

source_dll="$REPO_ROOT/electron/bin/scs-telemetry.dll"
if [[ ! -f "$source_dll" ]]; then
  echo "Telemetry plugin DLL not found: $source_dll" >&2
  exit 3
fi

override=""
if [[ "$env_dir_var" == "TRUCKNAV_ATS_DIR" ]]; then
  override="${TRUCKNAV_ATS_DIR:-}"
else
  override="${TRUCKNAV_ETS2_DIR:-}"
fi

game_dir="$(find_steam_game_dir "$app_id" "$game_dir_name" "$override" || true)"
if [[ -z "$game_dir" ]]; then
  echo "$game_label is not installed or could not be found." >&2
  exit 4
fi

plugin_dir="$game_dir/bin/win_x64/plugins"
if [[ ! -d "$game_dir/bin/win_x64" ]]; then
  echo "$game_label Windows/Proton game files were not found:" >&2
  echo "  $game_dir/bin/win_x64" >&2
  echo >&2
  echo "Force $game_label to use Proton in Steam Compatibility, then launch it once." >&2
  exit 5
fi

mkdir -p "$plugin_dir"
dest="$plugin_dir/scs-telemetry.dll"

if [[ -f "$dest" ]] && cmp -s "$source_dll" "$dest"; then
  echo "$game_label telemetry plugin is already current."
else
  cp -f "$source_dll" "$dest"
  echo "Installed $game_label telemetry plugin:"
  echo "  $dest"
fi
