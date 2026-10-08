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
  ':(exclude)public/sprites/ats/**' \
  ':(exclude)public/sprites/ets2/**' || \
  ! git diff --cached --quiet -- \
  . \
  ':(exclude)public/data/ats/**' \
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

previous_stash="$(git rev-parse -q --verify refs/stash || true)"

git stash push -m "TruckNav automatic sprite backup" -- \
  public/sprites/ats public/sprites/ets2

sprite_stash="$(git rev-parse -q --verify refs/stash || true)"
if [[ "$sprite_stash" == "$previous_stash" ]]; then
  sprite_stash=""
fi

restore_sprite_stash() {
  [[ -n "$sprite_stash" ]] || return 0

  if [[ "$(git rev-parse -q --verify refs/stash || true)" != "$sprite_stash" ]]; then
    echo "Stash order changed; sprite backup retained." >&2
    return 7
  fi

  echo "Restoring local sprite files..."
  if ! git stash pop --index 'stash@{0}'; then
    echo "Sprite restore failed; backup retained in Git stash." >&2
    return 7
  fi

  sprite_stash=""
}

trap 'restore_sprite_stash' EXIT

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
echo "Restart or reload TruckNav to use the updated files."
