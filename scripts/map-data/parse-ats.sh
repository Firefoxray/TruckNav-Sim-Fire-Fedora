#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_ROOT="${TRUCKNAV_MAP_TOOLS_ROOT:-$REPO_ROOT/.tools/map-data}"
SETUP_SCRIPT="$REPO_ROOT/scripts/map-data/setup-map-tools.sh"
OUT_DIR="${TRUCKNAV_ATS_PARSE_DIR:-$REPO_ROOT/build/map-data/ats-parser}"
ATS_APP_ID="270880"

if [[ ! -f "$TOOLS_ROOT/env.sh" ]]; then
    "$SETUP_SCRIPT"
fi

# shellcheck disable=SC1090
source "$TOOLS_ROOT/env.sh"

find_ats_dir() {
    if [[ -n "${TRUCKNAV_ATS_DIR:-}" && -d "$TRUCKNAV_ATS_DIR" ]]; then
        printf '%s\n' "$TRUCKNAV_ATS_DIR"
        return 0
    fi

    local manifest
    manifest="$(find         "$HOME/.local/share/Steam"         "$HOME/.steam"         "$HOME/.var/app/com.valvesoftware.Steam"         /mnt         "/run/media/$USER"         -maxdepth 7 -type f -name "appmanifest_${ATS_APP_ID}.acf"         -print 2>/dev/null | head -n 1 || true)"

    if [[ -z "$manifest" ]]; then
        return 1
    fi

    local candidate
    candidate="$(dirname "$manifest")/common/American Truck Simulator"
    [[ -d "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
}

ATS_DIR="$(find_ats_dir || true)"
if [[ -z "$ATS_DIR" ]]; then
    echo "Could not find the ATS install automatically." >&2
    echo "Set TRUCKNAV_ATS_DIR and rerun, for example:" >&2
    echo "  TRUCKNAV_ATS_DIR='/path/to/American Truck Simulator' $0" >&2
    exit 2
fi

if [[ ! -f "$ATS_DIR/dlc_sd.scs" ]]; then
    echo "South Dakota archive not found: $ATS_DIR/dlc_sd.scs" >&2
    exit 3
fi

mkdir -p "$OUT_DIR"

echo "=== ATS parser run ==="
echo "ATS:    $ATS_DIR"
echo "Output: $OUT_DIR"
echo "Node:   $(node --version)"
echo

(
    cd "$TRUCKNAV_MAPS_DIR"
    NODE_OPTIONS="--max-old-space-size=8192" ./node_modules/.bin/parser         -i "$ATS_DIR"         -o "$OUT_DIR"
)

echo
echo "=== South Dakota validation ==="
python3 - "$OUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
version = root / "usa-version.txt"
countries_path = root / "usa-countries.json"
cities_path = root / "usa-cities.json"
roads_path = root / "usa-roads.json"

print("ATS version:", version.read_text(encoding="utf-8").strip() if version.exists() else "UNKNOWN")

def load(name: Path):
    if not name.exists():
        raise SystemExit(f"Missing parser output: {name}")
    return json.loads(name.read_text(encoding="utf-8"))

countries = load(countries_path)
cities = load(cities_path)
roads = load(roads_path)

sd_countries = [
    c for c in countries
    if "dakota" in str(c.get("name", "")).lower()
    or "dakota" in str(c.get("token", "")).lower()
]
sd_cities = [c for c in cities if c.get("dlcGuard") == 53]
sd_roads = [r for r in roads if r.get("dlcGuard") == 53]

print("Country entries mentioning Dakota:", len(sd_countries))
for c in sd_countries[:10]:
    print("  ", c.get("token"), "|", c.get("name"), "| country id:", c.get("id"))

print("Cities with DLC guard 53:", len(sd_cities))
print("Roads with DLC guard 53:", len(sd_roads))

if not sd_roads:
    raise SystemExit("ERROR: parser produced no South Dakota roads (DLC guard 53).")

print("South Dakota parser validation: OK")
PY

echo
echo "Parser step complete."
echo "Keep this directory; the next stage will generate PMTiles and routing data from it:"
echo "  $OUT_DIR"
