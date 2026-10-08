#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${TRUCKNAV_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$REPO_ROOT"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 2
  }
}

require_cmd git
require_cmd npm

if ! git diff --quiet -- \
  . \
  ':(exclude)public/data/ats/**' \
  ':(exclude)public/data/ets2/**' \
  ':(exclude)public/sprites/ats/**' \
  ':(exclude)public/sprites/ets2/**' || \
  ! git diff --cached --quiet -- \
  . \
  ':(exclude)public/data/ats/**' \
  ':(exclude)public/data/ets2/**' \
  ':(exclude)public/sprites/ats/**' \
  ':(exclude)public/sprites/ets2/**'
then
  echo "Refusing to update because tracked source files have local changes." >&2
  echo "Commit, stash, or discard those source changes first." >&2
  git status --short --untracked-files=no >&2 || true
  exit 3
fi

branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ -z "$branch" ]]; then
  echo "Cannot update from a detached HEAD." >&2
  exit 4
fi

upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [[ -z "$upstream" ]]; then
  upstream="origin/$branch"
fi

remote="${upstream%%/*}"
remote_branch="${upstream#*/}"

echo "=== TruckNav Linux app update ==="
echo "Branch:   $branch"
echo "Upstream: $upstream"
echo

echo "Checking GitHub..."
git fetch "$remote" "$remote_branch"

old_head="$(git rev-parse HEAD)"
target_head="$(git rev-parse "$upstream")"

if [[ "$old_head" == "$target_head" ]]; then
  echo "TruckNav Linux is already up to date."
  exit 0
fi

if ! git merge-base --is-ancestor "$old_head" "$target_head"; then
  echo "Local branch and upstream have diverged; refusing automatic update." >&2
  echo "Resolve the Git history manually before using the updater again." >&2
  exit 5
fi

changed_files="$(git diff --name-only "$old_head" "$target_head")"

# Never overwrite generated files that exist locally but are not tracked yet.
# Git normally refuses these merges too, but catch them before stashing anything.
while IFS= read -r untracked_file; do
  if grep -Fxq -- "$untracked_file" <<<"$changed_files"; then
    echo "Update would overwrite untracked local file: $untracked_file" >&2
    echo "Move or back up that file manually before updating." >&2
    exit 6
  fi
done < <(git ls-files --others --exclude-standard)

previous_stash="$(git rev-parse -q --verify refs/stash || true)"

# Generated map files can contain tracked local edits too. Save those
# alongside the two sprite atlases. Untracked map assets are left in place.
# A pathspec that only contains untracked files causes git stash to fail, so
# include a game data folder only when Git already tracks something there.
stash_paths=(public/sprites/ats public/sprites/ets2)
for game in ats ets2; do
  if [[ -n "$(git ls-files -- "public/data/$game")" ]]; then
    stash_paths+=("public/data/$game")
  fi
done
git stash push -m "TruckNav automatic generated map backup" -- "${stash_paths[@]}"

sprite_stash="$(git rev-parse -q --verify refs/stash || true)"
if [[ "$sprite_stash" == "$previous_stash" ]]; then
  sprite_stash=""
fi

restore_sprite_stash() {
  [[ -n "$sprite_stash" ]] || return 0

  if [[ "$(git rev-parse -q --verify refs/stash || true)" != "$sprite_stash" ]]; then
    echo "Stash order changed; generated map backup retained." >&2
    return 7
  fi

  echo "Restoring local generated map and sprite files..."
  if ! git stash pop --index 'stash@{0}'; then
    echo "Generated map restore failed; backup retained in Git stash." >&2
    return 7
  fi

  sprite_stash=""
}

trap 'restore_sprite_stash' EXIT

# There is an actual update. Stop the running dashboard and telemetry before
# changing files so the Nuxt dev process cannot reload an inconsistent tree.
# The update job is detached by the Linux API, so it continues after the web
# dashboard disconnects. Never automatically relaunch after the update.
echo
echo "Update found. Stopping TruckNav web app and telemetry (ATS/ETS2 keep running)..."
bash "$REPO_ROOT/scripts/linux/stop-trucknav.sh"

echo "Fast-forwarding to ${target_head:0:10}..."
git merge --ff-only "$target_head"

if ! restore_sprite_stash; then
  trap - EXIT
  exit 7
fi
trap - EXIT

if grep -Eq '^(package.json|package-lock.json)$' <<<"$changed_files"; then
  echo
  echo "Node dependencies changed; refreshing node_modules..."
  npm ci
fi

echo
echo "Validating updated application..."
npm run build

echo
echo "Refreshing installed TruckNav Linux launcher..."
if [[ -x "$REPO_ROOT/scripts/linux/install-desktop-files.sh" ]]; then
  if [[ "$branch" == "master" ]]; then
    bash "$REPO_ROOT/scripts/linux/install-desktop-files.sh" --activate stable
  else
    bash "$REPO_ROOT/scripts/linux/install-desktop-files.sh" --activate testing
  fi
fi

echo
echo "TruckNav Linux updated successfully."
echo "Old commit: ${old_head:0:10}"
echo "New commit: ${target_head:0:10}"
echo "TruckNav web app and telemetry are stopped. They will not restart automatically."
echo "To launch again: bash scripts/linux/launch-trucknav.sh ats"
