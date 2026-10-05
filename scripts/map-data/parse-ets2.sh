#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_ROOT="${TRUCKNAV_MAP_TOOLS_ROOT:-$REPO_ROOT/.tools/map-data}"
SETUP_SCRIPT="$REPO_ROOT/scripts/map-data/setup-map-tools.sh"
OUT_DIR="${TRUCKNAV_ETS2_PARSE_DIR:-$REPO_ROOT/build/map-data/ets2-parser}"
ETS2_APP_ID="227300"

if [[ ! -f "$TOOLS_ROOT/env.sh" ]]; then
    bash "$SETUP_SCRIPT"
fi

# shellcheck disable=SC1090
source "$TOOLS_ROOT/env.sh"

find_ets2_dir() {
    if [[ -n "${TRUCKNAV_ETS2_DIR:-}" && -d "$TRUCKNAV_ETS2_DIR" ]]; then
        printf '%s\n' "$TRUCKNAV_ETS2_DIR"
        return 0
    fi

    local manifest
    manifest="$(find         "$HOME/.local/share/Steam"         "$HOME/.steam"         "$HOME/.var/app/com.valvesoftware.Steam"         /mnt         "/run/media/$USER"         -maxdepth 7 -type f -name "appmanifest_${ETS2_APP_ID}.acf"         -print 2>/dev/null | head -n 1 || true)"

    [[ -n "$manifest" ]] || return 1

    local candidate
    candidate="$(dirname "$manifest")/common/Euro Truck Simulator 2"
    [[ -d "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
}

ETS2_DIR="$(find_ets2_dir || true)"
if [[ -z "$ETS2_DIR" ]]; then
    echo "Could not find the ETS2 install automatically." >&2
    echo "Set TRUCKNAV_ETS2_DIR and rerun, for example:" >&2
    echo "  TRUCKNAV_ETS2_DIR='/path/to/Euro Truck Simulator 2' $0" >&2
    exit 2
fi

for required in base.scs def.scs version.scs; do
    if [[ ! -f "$ETS2_DIR/$required" ]]; then
        echo "Missing ETS2 core archive: $ETS2_DIR/$required" >&2
        exit 3
    fi
done

mkdir -p "$OUT_DIR"

echo "=== ETS2 parser run ==="
echo "ETS2:   $ETS2_DIR"
echo "Output: $OUT_DIR"
echo "Node:   $(node --version)"
echo

(
    cd "$TRUCKNAV_MAPS_DIR"
    NODE_OPTIONS="--max-old-space-size=8192" ./node_modules/.bin/parser         -i "$ETS2_DIR"         -o "$OUT_DIR"
)

echo
echo "=== ETS2 parser validation ==="
python3 - "$OUT_DIR" <<'PY'
import json
import sys
from collections import Counter
from pathlib import Path

root = Path(sys.argv[1])
version = root / "europe-version.txt"
roads_path = root / "europe-roads.json"
nodes_path = root / "europe-nodes.json"
cities_path = root / "europe-cities.json"
prefabs_path = root / "europe-prefabs.json"

for p in (version, roads_path, nodes_path, cities_path, prefabs_path):
    if not p.exists():
        raise SystemExit(f"Missing parser output: {p}")

roads = json.loads(roads_path.read_text(encoding="utf-8"))
nodes = json.loads(nodes_path.read_text(encoding="utf-8"))
cities = json.loads(cities_path.read_text(encoding="utf-8"))

if not roads or not nodes:
    raise SystemExit("ETS2 parser produced no roads or nodes")

guards = Counter()
for item in roads:
    guard = item.get("dlcGuard")
    if isinstance(guard, (int, float)):
        guards[int(guard)] += 1

print("ETS2 version:", version.read_text(encoding="utf-8").strip())
print(f"nodes:  {len(nodes):,}")
print(f"roads:  {len(roads):,}")
print(f"cities: {len(cities):,}")
print("road DLC guards:", dict(sorted(guards.items())))
print("ETS2 parser validation: OK")
PY

echo
echo "ETS2 parser step complete."
echo "Output:"
echo "  $OUT_DIR"
