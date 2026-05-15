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
in_git_repo=false
lockfile_tracked=false
lockfile_clean_before_install=false
lockfile_has_staged_changes=false

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  in_git_repo=true
  if git ls-files --error-unmatch package-lock.json >/dev/null 2>&1; then
    lockfile_tracked=true
    if git diff --quiet -- package-lock.json; then
      lockfile_clean_before_install=true
    fi
    if ! git diff --cached --quiet -- package-lock.json; then
      lockfile_has_staged_changes=true
    fi
  fi
fi

restore_lockfile_after_npm_dependency_install() {
  # npm lifecycle scripts, npm-force-resolutions, npm ci, and npm install can
  # rewrite package-lock.json as an install side effect. Restore the tracked
  # lockfile only when it was completely clean before dependency installation.
  if [[ "$in_git_repo" != true || "$lockfile_tracked" != true ]]; then
    return
  fi

  # Staged lockfile changes are treated as intentional user work. Do not
  # restore in that case, even if npm also changes the working tree.
  if [[ "$lockfile_has_staged_changes" == true ]]; then
    echo "Warning: npm dependency install may have modified package-lock.json, but staged lockfile changes were found; leaving it unchanged." >&2
    return
  fi

  if [[ "$lockfile_clean_before_install" == true ]] && ! git diff --quiet -- package-lock.json; then
    git restore package-lock.json
    echo "npm dependency install modified package-lock.json; restored tracked lockfile to keep working tree clean." >&2
  fi
}

if [[ -f package-lock.json ]]; then
  echo "package-lock.json found; installing locked dependencies with npm ci..."
  if npm ci; then
    echo "npm ci completed successfully."
  else
    echo "npm ci failed; falling back to npm install. package-lock.json will be restored if npm changes the tracked copy." >&2
    npm install
  fi
else
  echo "package-lock.json not found; falling back to npm install." >&2
  npm install
fi

restore_lockfile_after_npm_dependency_install

echo "Installing TruckNav desktop files and launcher wrappers..."
"$REPO_ROOT/scripts/linux/install-desktop-files.sh"

echo
"$REPO_ROOT/scripts/linux/check-status.sh"

echo
echo "Done. Search for 'TruckNav Linux Launcher' or 'TruckNav Sim' in your application launcher."
