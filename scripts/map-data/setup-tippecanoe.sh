#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_ROOT="${TRUCKNAV_MAP_TOOLS_ROOT:-$REPO_ROOT/.tools/map-data}"
TIP_ROOT="$TOOLS_ROOT/tippecanoe"
TIP_SRC="$TIP_ROOT/src"
TIP_BIN="$TIP_ROOT/bin"
TIP_VERSION="2.79.0"

if [[ -x "$TIP_BIN/tippecanoe" ]]; then
    echo "Tippecanoe already ready: $("$TIP_BIN/tippecanoe" --version 2>&1 | head -n1)"
    exit 0
fi

missing=()
for cmd in git make gcc g++; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if ((${#missing[@]})); then
    echo "Missing build tools: ${missing[*]}" >&2
    echo "On Fedora install them with:" >&2
    echo "  sudo dnf install git make gcc gcc-c++ sqlite-devel zlib-devel" >&2
    exit 2
fi

mkdir -p "$TIP_ROOT"

if [[ ! -d "$TIP_SRC/.git" ]]; then
    echo "Cloning Tippecanoe $TIP_VERSION..."
    git clone --depth 1 --branch "$TIP_VERSION"         https://github.com/felt/tippecanoe.git "$TIP_SRC"
else
    echo "Resetting Tippecanoe to $TIP_VERSION..."
    git -C "$TIP_SRC" fetch --depth 1 origin "refs/tags/$TIP_VERSION:refs/tags/$TIP_VERSION"
    git -C "$TIP_SRC" checkout --detach "$TIP_VERSION"
    git -C "$TIP_SRC" reset --hard "$TIP_VERSION"
fi

echo "Building isolated Tippecanoe..."
if ! make -C "$TIP_SRC" -j"$(nproc)" tippecanoe tippecanoe-decode; then
    echo >&2
    echo "Tippecanoe build failed." >&2
    echo "On Fedora make sure the native dependencies are installed:" >&2
    echo "  sudo dnf install make gcc gcc-c++ sqlite-devel zlib-devel" >&2
    exit 3
fi

mkdir -p "$TIP_BIN"
cp "$TIP_SRC/tippecanoe" "$TIP_BIN/"
cp "$TIP_SRC/tippecanoe-decode" "$TIP_BIN/"

echo
echo "Tippecanoe ready:"
"$TIP_BIN/tippecanoe" --version || true
echo "Binary: $TIP_BIN/tippecanoe"
