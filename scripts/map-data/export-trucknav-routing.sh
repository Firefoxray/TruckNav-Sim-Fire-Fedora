#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_ROOT="${TRUCKNAV_MAP_TOOLS_ROOT:-$REPO_ROOT/.tools/map-data}"
PARSE_DIR="${TRUCKNAV_ATS_PARSE_DIR:-$REPO_ROOT/build/map-data/ats-parser}"
GENERATED_ROOT="${TRUCKNAV_ATS_GENERATED_DIR:-$REPO_ROOT/build/map-data/ats-generated}"
GRAPH_DIR="$GENERATED_ROOT/graph"
OUT_DIR="${TRUCKNAV_ATS_TRUCKNAV_DIR:-$REPO_ROOT/build/map-data/ats-trucknav/roadnetwork}"

if [[ ! -f "$TOOLS_ROOT/env.sh" ]]; then
    echo "Map tooling is not bootstrapped. Run:" >&2
    echo "  bash scripts/map-data/setup-map-tools.sh" >&2
    exit 2
fi

# shellcheck disable=SC1090
source "$TOOLS_ROOT/env.sh"

for required in     "$PARSE_DIR/usa-nodes.json"     "$PARSE_DIR/usa-roads.json"     "$PARSE_DIR/usa-prefabs.json"     "$GRAPH_DIR/usa-graph.json"     "$GRAPH_DIR/usa-roundabouts.json"
do
    if [[ ! -f "$required" ]]; then
        echo "Missing required source file: $required" >&2
        echo "Complete the source-data generation first." >&2
        exit 3
    fi
done

mkdir -p "$OUT_DIR"

EXPORTER_SRC="$REPO_ROOT/scripts/map-data/trucknav-export.ts"
EXPORTER_DST="$TRUCKNAV_MAPS_DIR/packages/clis/generator/trucknav-export.ts"
cp "$EXPORTER_SRC" "$EXPORTER_DST"

echo "=== TruckNav ATS binary graph export ==="
echo "Parser: $PARSE_DIR"
echo "Graph:  $GRAPH_DIR"
echo "Output: $OUT_DIR"
echo

(
    cd "$TRUCKNAV_MAPS_DIR"
    NODE_OPTIONS="--max-old-space-size=8192" ./node_modules/.bin/tsx         "$EXPORTER_DST"         usa         "$PARSE_DIR"         "$GRAPH_DIR"         "$OUT_DIR"
)

echo
echo "=== Binary sanity check ==="
python3 - "$OUT_DIR" <<'PY'
import json
import struct
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

sd_edges = manifest["dlcEncoding"]["southDakotaEdges"]
if sd_edges <= 0:
    raise SystemExit("no South Dakota-gated routing edges were exported")

print(f"edges:               {edges:,}")
print(f"nodes:               {manifest['graph']['nodes']:,}")
print(f"geometry points:     {manifest['graph']['geometryPoints']:,}")
print(f"South Dakota edges:  {sd_edges:,}")
print(f"composite DLC edges: {manifest['dlcEncoding']['compositeEdges']:,}")
print(f"roundabout edges:    {manifest['navigation']['roundaboutEdges']:,}")
print(f"skipped guards:       {manifest.get('skippedUnknownDlcGuards', {})}")
print("TruckNav binary sanity check: OK")
PY

echo
echo "TruckNav routing binaries are ready in:"
echo "  $OUT_DIR"
