#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_ROOT="${TRUCKNAV_MAP_TOOLS_ROOT:-$REPO_ROOT/.tools/map-data}"
PARSE_DIR="${TRUCKNAV_ETS2_PARSE_DIR:-$REPO_ROOT/build/map-data/ets2-parser}"
GENERATED_ROOT="${TRUCKNAV_ETS2_GENERATED_DIR:-$REPO_ROOT/build/map-data/ets2-generated}"
GRAPH_DIR="$GENERATED_ROOT/graph"
OUT_DIR="${TRUCKNAV_ETS2_TRUCKNAV_DIR:-$REPO_ROOT/build/map-data/ets2-trucknav/roadnetwork}"

if [[ ! -f "$TOOLS_ROOT/env.sh" ]]; then
    echo "Map tooling is not bootstrapped. Run:" >&2
    echo "  bash scripts/map-data/setup-map-tools.sh" >&2
    exit 2
fi

# shellcheck disable=SC1090
source "$TOOLS_ROOT/env.sh"

for required in     "$PARSE_DIR/europe-nodes.json"     "$PARSE_DIR/europe-roads.json"     "$PARSE_DIR/europe-prefabs.json"     "$GRAPH_DIR/europe-graph.json"     "$GRAPH_DIR/europe-roundabouts.json"
do
    if [[ ! -f "$required" ]]; then
        echo "Missing required source file: $required" >&2
        echo "Complete the ETS2 source-data generation first." >&2
        exit 3
    fi
done

mkdir -p "$OUT_DIR"

EXPORTER_SRC="$REPO_ROOT/scripts/map-data/trucknav-export.ts"
EXPORTER_DST="$TRUCKNAV_MAPS_DIR/packages/clis/generator/trucknav-export.ts"
cp "$EXPORTER_SRC" "$EXPORTER_DST"

echo "=== TruckNav ETS2 binary graph export ==="
echo "Parser: $PARSE_DIR"
echo "Graph:  $GRAPH_DIR"
echo "Output: $OUT_DIR"
echo

(
    cd "$TRUCKNAV_MAPS_DIR"
    NODE_OPTIONS="--max-old-space-size=8192" ./node_modules/.bin/tsx         "$EXPORTER_DST"         europe         "$PARSE_DIR"         "$GRAPH_DIR"         "$OUT_DIR"
)

echo
echo "=== ETS2 binary sanity check ==="
python3 - "$OUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
graph = root / "graph.bin"
geometry = root / "geometry.bin"
nodes = root / "nodes.bin"
manifest_path = root / "trucknav-graph-manifest.json"

for p in (graph, geometry, nodes, manifest_path):
    if not p.is_file():
        raise SystemExit(f"missing expected output: {p}")

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
stride = manifest["graph"]["stride"]
edges = manifest["graph"]["edges"]

if graph.stat().st_size != edges * stride * 4:
    raise SystemExit(
        f"graph.bin size mismatch: {graph.stat().st_size} != {edges * stride * 4}"
    )
if geometry.stat().st_size % 8 != 0:
    raise SystemExit("geometry.bin is not aligned to [lon,lat] float32 pairs")
if nodes.stat().st_size % 16 != 0:
    raise SystemExit("nodes.bin is not aligned to 16-byte UID entries")

newest = manifest["dlcEncoding"].get("newestDlcEdges", 0)
if newest <= 0:
    raise SystemExit("no Nordic Horizons-gated routing edges were exported")

print(f"edges:                {edges:,}")
print(f"nodes:                {manifest['graph']['nodes']:,}")
print(f"geometry points:      {manifest['graph']['geometryPoints']:,}")
print(f"Nordic Horizon edges: {newest:,}")
print(f"composite DLC edges:  {manifest['dlcEncoding']['compositeEdges']:,}")
print(f"roundabout edges:     {manifest['navigation']['roundaboutEdges']:,}")
print(f"skipped guards:        {manifest.get('skippedUnknownDlcGuards', {})}")
print("TruckNav ETS2 binary sanity check: OK")
PY

echo
echo "TruckNav ETS2 routing binaries are ready in:"
echo "  $OUT_DIR"
