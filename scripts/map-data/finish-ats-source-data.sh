#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_ROOT="${TRUCKNAV_MAP_TOOLS_ROOT:-$REPO_ROOT/.tools/map-data}"
PARSE_DIR="${TRUCKNAV_ATS_PARSE_DIR:-$REPO_ROOT/build/map-data/ats-parser}"
OUT_ROOT="${TRUCKNAV_ATS_GENERATED_DIR:-$REPO_ROOT/build/map-data/ats-generated}"
GRAPH_DIR="$OUT_ROOT/graph"
SPRITES_DIR="$OUT_ROOT/sprites"

if [[ ! -f "$TOOLS_ROOT/env.sh" ]]; then
    echo "Map tooling is not bootstrapped. Run:" >&2
    echo "  bash scripts/map-data/setup-map-tools.sh" >&2
    exit 2
fi

# shellcheck disable=SC1090
source "$TOOLS_ROOT/env.sh"

GENERATOR="$TRUCKNAV_MAPS_DIR/node_modules/.bin/generator"

for required in     "$PARSE_DIR/usa-nodes.json"     "$PARSE_DIR/usa-prefabs.json"     "$GRAPH_DIR/usa-graph.json"
do
    if [[ ! -f "$required" ]]; then
        echo "Missing required generated file: $required" >&2
        echo "Run the full source-data generator first:" >&2
        echo "  bash scripts/map-data/generate-ats-source-data.sh" >&2
        exit 3
    fi
done

mkdir -p "$GRAPH_DIR" "$SPRITES_DIR"

echo "=== Resume ATS source-data generation ==="
echo "Parser input: $PARSE_DIR"
echo "Output root:  $OUT_ROOT"
echo

echo "[4/5] Regenerating prefab curves and roundabout metadata..."
(
    cd "$TRUCKNAV_MAPS_DIR"
    "$GENERATOR" prefab-curves         -m usa         -i "$PARSE_DIR"         -o "$GRAPH_DIR"

    "$GENERATOR" roundabouts         -m usa         -i "$PARSE_DIR"         -g "$GRAPH_DIR"         -o "$GRAPH_DIR"
)

echo
echo "[5/5] Generating fresh ATS sprite sheet..."
(
    cd "$TRUCKNAV_MAPS_DIR"
    "$GENERATOR" spritesheet         -m usa         -i "$PARSE_DIR"         -o "$SPRITES_DIR"
)

echo
echo "=== Completed generated files ==="
find "$GRAPH_DIR" "$SPRITES_DIR" -maxdepth 1 -type f -printf '%p\t%k KiB\n' | sort

echo
echo "Resume stage complete."
