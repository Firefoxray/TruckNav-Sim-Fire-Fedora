#!/usr/bin/env bash
set -euo pipefail

TRUCKNAV_ATS_APP_ID="${TRUCKNAV_ATS_APP_ID:-270880}"
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
