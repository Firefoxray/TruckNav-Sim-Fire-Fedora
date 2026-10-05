#!/usr/bin/env bash
set -euo pipefail

TRUCKNAV_ATS_APP_ID="${TRUCKNAV_ATS_APP_ID:-270880}"
TRUCKNAV_ETS2_APP_ID="${TRUCKNAV_ETS2_APP_ID:-227300}"
TRUCKNAV_GAME="${TRUCKNAV_GAME:-ats}"
TRUCKNAV_URL="${TRUCKNAV_URL:-http://127.0.0.1:3000/}"

find_repo_root() {
  if [[ -n "${TRUCKNAV_REPO_ROOT:-}" && -f "$TRUCKNAV_REPO_ROOT/package.json" ]]; then
    cd "$TRUCKNAV_REPO_ROOT" && pwd
    return
  fi

  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/package.json" && -f "$dir/nuxt.config.ts" ]]; then
      cd "$dir" && pwd
      return
    fi
    dir="$(dirname "$dir")"
  done

  if git_root="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null)" && [[ -f "$git_root/package.json" ]]; then
    cd "$git_root" && pwd
    return
  fi

  echo "Could not detect the TruckNav-Sim repository root." >&2
  exit 1
}

REPO_ROOT="$(find_repo_root)"
TELEMETRY_EXE="$REPO_ROOT/electron/bin/TruckNavTelemetry.exe"
PID_DIR="${XDG_RUNTIME_DIR:-/tmp}/trucknav-sim"
WEB_PID_FILE="$PID_DIR/web.pid"
TELEMETRY_PID_FILE="$PID_DIR/telemetry.pid"
TELEMETRY_GAME_FILE="$PID_DIR/telemetry.game"
mkdir -p "$PID_DIR"

require_command() {
  local cmd="$1"
  local hint="${2:-Install it and try again.}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd. $hint" >&2
    exit 1
  fi
}

is_pid_running() {
  local pid="${1:-}"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

pid_from_file() {
  local file="$1"
  [[ -f "$file" ]] && cat "$file" || true
}

wait_for_url() {
  local url="$1"
  local attempts="${2:-30}"
  for ((i = 1; i <= attempts; i++)); do
    if command -v curl >/dev/null 2>&1 && curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}


# Resolve a Steam game's install directory without recursively crawling /mnt.
# Steam already records every library in libraryfolders.vdf, so checking those
# known roots is effectively instant even on hosts with large mounted disks.
find_steam_game_dir() {
  local app_id="$1"
  local game_dir_name="$2"
  local override="${3:-}"

  if [[ -n "$override" && -d "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  local -a steam_roots=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.steam/steam"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
  )

  local root manifest candidate library_file raw_path library
  local -A seen=()

  check_library() {
    local lib="$1"
    [[ -n "$lib" ]] || return 1
    [[ -z "${seen[$lib]:-}" ]] || return 1
    seen["$lib"]=1

    manifest="$lib/steamapps/appmanifest_${app_id}.acf"
    candidate="$lib/steamapps/common/$game_dir_name"

    if [[ -f "$manifest" && -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    return 1
  }

  for root in "${steam_roots[@]}"; do
    [[ -d "$root" ]] || continue

    if check_library "$root"; then
      return 0
    fi

    library_file="$root/steamapps/libraryfolders.vdf"
    [[ -f "$library_file" ]] || continue

    while IFS= read -r raw_path; do
      library="$raw_path"
      library="${library//\\\\/\\}"
      if check_library "$library"; then
        return 0
      fi
    done < <(
      sed -nE 's/^[[:space:]]*"path"[[:space:]]+"(.*)"[[:space:]]*$/\1/p'         "$library_file"
    )
  done

  return 1
}


telemetry_port_open() {
  ss -lnt 2>/dev/null | grep -Eq '[:.]30001[[:space:]]'
}
