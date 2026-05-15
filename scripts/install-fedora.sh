#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TRUCKNAV_REPO_ROOT="$REPO_ROOT"

cd "$REPO_ROOT"

if ! command -v dnf >/dev/null 2>&1; then
  echo "This installer is intended for Fedora systems with dnf." >&2
  exit 1
fi

echo "Installing Fedora dependencies..."
sudo dnf install -y nodejs npm git protontricks kde-cli-tools konsole python3 python3-tkinter curl procps-ng

echo "Installing npm dependencies..."
if [[ -f package-lock.json ]]; then
  echo "package-lock.json found; installing locked dependencies with npm ci..."
  if npm ci; then
    echo "npm ci completed successfully."
  else
    echo "npm ci failed; falling back to npm install. package-lock.json may be updated by npm." >&2
    npm install
  fi
else
  echo "package-lock.json not found; falling back to npm install." >&2
  npm install
fi

echo "Installing TruckNav desktop files and launcher wrappers..."
"$REPO_ROOT/scripts/linux/install-desktop-files.sh"

echo
"$REPO_ROOT/scripts/linux/check-status.sh"

echo
echo "Done. Search for 'TruckNav Linux Launcher' or 'TruckNav Sim' in your application launcher."
