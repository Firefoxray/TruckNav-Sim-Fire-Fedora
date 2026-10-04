#!/usr/bin/env bash
set -euo pipefail

# Preflight helper for rebuilding American Truck Simulator map data.
# This script does not modify ATS, Steam, or TruckNav.

ATS_APP_ID="270880"

version_ge() {
    local have="$1"
    local want="$2"
    printf '%s\n%s\n' "$want" "$have" | sort -V -C
}

print_cmd_version() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        printf '%-12s %s\n' "$cmd:" "$("$cmd" --version 2>/dev/null | head -n 1)"
    else
        printf '%-12s MISSING\n' "$cmd:"
    fi
}

echo "=== Tool versions ==="
print_cmd_version git
print_cmd_version node
print_cmd_version npm
print_cmd_version python3

if command -v node >/dev/null 2>&1; then
    NODE_VERSION="$(node -p 'process.versions.node')"
    if version_ge "$NODE_VERSION" "24.13.0"; then
        echo "Node check: OK (>= 24.13.0)"
    else
        echo "Node check: NEEDS UPDATE (truckermudgeon/maps currently requires Node >= 24.13.0)"
    fi
fi

echo
echo "=== Looking for ATS Steam manifest ==="

declare -a SEARCH_ROOTS=()
for root in \
    "$HOME/.steam" \
    "$HOME/.local/share/Steam" \
    "$HOME/.var/app/com.valvesoftware.Steam" \
    "/mnt" \
    "/run/media/$USER"
do
    [[ -e "$root" ]] && SEARCH_ROOTS+=("$root")
done

declare -a MANIFESTS=()
if ((${#SEARCH_ROOTS[@]})); then
    while IFS= read -r path; do
        [[ -n "$path" ]] && MANIFESTS+=("$path")
    done < <(
        find "${SEARCH_ROOTS[@]}" \
            -maxdepth 7 \
            -type f \
            -name "appmanifest_${ATS_APP_ID}.acf" \
            -print 2>/dev/null | sort -u
    )
fi

if [[ -n "${TRUCKNAV_ATS_DIR:-}" ]]; then
    ATS_DIR="$TRUCKNAV_ATS_DIR"
elif ((${#MANIFESTS[@]} == 1)); then
    STEAMAPPS_DIR="$(dirname "${MANIFESTS[0]}")"
    ATS_DIR="$STEAMAPPS_DIR/common/American Truck Simulator"
else
    ATS_DIR=""
fi

if ((${#MANIFESTS[@]})); then
    printf '%s\n' "${MANIFESTS[@]}"
else
    echo "No ATS appmanifest found automatically."
fi

echo
echo "=== ATS directory ==="
if [[ -n "$ATS_DIR" && -d "$ATS_DIR" ]]; then
    echo "$ATS_DIR"
else
    echo "ATS directory could not be selected automatically."
    if ((${#MANIFESTS[@]} > 1)); then
        echo "Multiple ATS manifests were found. Set TRUCKNAV_ATS_DIR to the active install directory."
    fi
    echo
    echo "Example:"
    echo "  TRUCKNAV_ATS_DIR='/path/to/American Truck Simulator' $0"
    exit 2
fi

echo
echo "=== Core files ==="
for file in base.scs def.scs version.sii; do
    if [[ -e "$ATS_DIR/$file" ]]; then
        printf 'FOUND   %s\n' "$file"
    else
        printf 'MISSING %s\n' "$file"
    fi
done

echo
echo "=== South Dakota candidates ==="
mapfile -t SD_FILES < <(find "$ATS_DIR" -maxdepth 1 -type f \( -iname 'dlc_sd*.scs' -o -iname '*south*dakota*.scs' \) -printf '%f\n' 2>/dev/null | sort)
if ((${#SD_FILES[@]})); then
    printf '%s\n' "${SD_FILES[@]}"
else
    echo "No obvious South Dakota .scs filename found."
fi

echo
echo "=== Installed map DLC .scs files ==="
find "$ATS_DIR" -maxdepth 1 -type f -name 'dlc_*.scs' -printf '%f\n' 2>/dev/null | sort

echo
echo "Preflight complete. Paste this output back into the chat."
