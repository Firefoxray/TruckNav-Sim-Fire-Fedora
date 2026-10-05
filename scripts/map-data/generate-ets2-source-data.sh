#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_ROOT="${TRUCKNAV_MAP_TOOLS_ROOT:-$REPO_ROOT/.tools/map-data}"
PARSE_DIR="${TRUCKNAV_ETS2_PARSE_DIR:-$REPO_ROOT/build/map-data/ets2-parser}"
OUT_ROOT="${TRUCKNAV_ETS2_GENERATED_DIR:-$REPO_ROOT/build/map-data/ets2-generated}"

if [[ ! -f "$TOOLS_ROOT/env.sh" ]]; then
    echo "Map tooling is not bootstrapped. Run:" >&2
    echo "  bash scripts/map-data/setup-map-tools.sh" >&2
    exit 2
fi

# shellcheck disable=SC1090
source "$TOOLS_ROOT/env.sh"

for required in     "$PARSE_DIR/europe-nodes.json"     "$PARSE_DIR/europe-roads.json"     "$PARSE_DIR/europe-prefabs.json"     "$PARSE_DIR/europe-countries.json"
do
    if [[ ! -f "$required" ]]; then
        echo "Missing parser output: $required" >&2
        echo "Run: bash scripts/map-data/parse-ets2.sh" >&2
        exit 3
    fi
done

MAP_DIR="$OUT_ROOT/map"
RAW_MAP_DIR="$OUT_ROOT/map-uncoalesced"
GRAPH_DIR="$OUT_ROOT/graph"
SPRITES_DIR="$OUT_ROOT/sprites"

mkdir -p "$MAP_DIR" "$RAW_MAP_DIR" "$GRAPH_DIR" "$SPRITES_DIR"

GENERATOR="$TRUCKNAV_MAPS_DIR/node_modules/.bin/generator"
if [[ ! -x "$GENERATOR" ]]; then
    echo "Generator executable not found: $GENERATOR" >&2
    exit 4
fi

echo "=== ETS2 generated source-data stage ==="
echo "Parser input: $PARSE_DIR"
echo "Output root:  $OUT_ROOT"
echo "Node:         $(node --version)"
echo

echo "[1/5] Generating normal ETS2 GeoJSON..."
(
    cd "$TRUCKNAV_MAPS_DIR"
    "$GENERATOR" map -m europe -i "$PARSE_DIR" -o "$MAP_DIR" -t geojson
)

echo
echo "[2/5] Generating uncoalesced ETS2 GeoJSON for route-geometry matching..."
(
    cd "$TRUCKNAV_MAPS_DIR"
    "$GENERATOR" map -m europe -i "$PARSE_DIR" -o "$RAW_MAP_DIR" -t geojson --skipCoalescing
)

echo
echo "[3/5] Generating directed ETS2 routing graph..."
(
    cd "$TRUCKNAV_MAPS_DIR"
    "$GENERATOR" graph -m europe -i "$PARSE_DIR" -o "$GRAPH_DIR"
)

echo
echo "[4/5] Generating prefab curves and roundabout metadata..."
(
    cd "$TRUCKNAV_MAPS_DIR"
    "$GENERATOR" prefab-curves -m europe -i "$PARSE_DIR" -o "$GRAPH_DIR"
    "$GENERATOR" roundabouts -m europe -i "$PARSE_DIR" -g "$GRAPH_DIR" -o "$GRAPH_DIR"
)

echo
echo "[5/5] Generating fresh ETS2 sprite sheet..."
(
    cd "$TRUCKNAV_MAPS_DIR"
    "$GENERATOR" spritesheet -m europe -i "$PARSE_DIR" -o "$SPRITES_DIR"
)

echo
echo "=== ETS2 generated files ==="
find "$OUT_ROOT" -maxdepth 2 -type f -printf '%p\t%k KiB\n' | sort

echo
echo "ETS2 source-data generation complete."
