#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

PARSE_DIR="${TRUCKNAV_ETS2_PARSE_DIR:-$REPO_ROOT/build/map-data/ets2-parser}"
GENERATED_ROOT="${TRUCKNAV_ETS2_TRUCKNAV_DIR:-$REPO_ROOT/build/map-data/ets2-trucknav}"

required=(
  "$PARSE_DIR/europe-version.txt"
  "$PARSE_DIR/europe-cities.json"
  "$GENERATED_ROOT/map-data/ets2-released.geojson"
  "$GENERATED_ROOT/map-data/trucknav-visual-manifest.json"
  "$GENERATED_ROOT/roadnetwork/trucknav-graph-manifest.json"
  "$GENERATED_ROOT/map-data/tiles/roads.mp3"
  "$GENERATED_ROOT/roadnetwork/graph.bin"
  "$GENERATED_ROOT/roadnetwork/geometry.bin"
  "$GENERATED_ROOT/roadnetwork/nodes.bin"
)

for path in "${required[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing generated ETS2 asset: $path" >&2
    echo "Run the ETS2 generation/export stages before finishing the runtime bundle." >&2
    exit 2
  fi
done

echo "=== Finishing TruckNav ETS2 runtime ==="

echo "[1/3] Generating current city/company data..."
python3 scripts/map-data/generate-ets2-aux-data.py   "$PARSE_DIR/europe-cities.json"   "$GENERATED_ROOT/map-data/ets2-released.geojson"   "$GENERATED_ROOT/map-data"

echo
echo "[2/3] Writing TruckNav Linux ETS2 map manifest..."
python3 scripts/map-data/write-trucknav-linux-map-manifest.py   ets2   "$PARSE_DIR/europe-version.txt"   "$GENERATED_ROOT/roadnetwork/trucknav-graph-manifest.json"   "$GENERATED_ROOT/map-data/trucknav-visual-manifest.json"   "$GENERATED_ROOT/map-data/trucknav-linux-map.json"

echo
echo "[3/3] Installing fresh ETS2 runtime bundle..."
bash scripts/map-data/prepare-ets2-test-bundle.sh

echo
echo "Fresh ETS2 runtime is ready."
echo "Reload TruckNav and select ETS2."
