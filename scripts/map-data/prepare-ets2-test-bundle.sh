#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REFERENCE_REPO="${TRUCKNAV_REFERENCE_REPO:-$(dirname "$REPO_ROOT")/TruckNav-Sim-Fire-Fedora}"
GENERATED_ROOT="${TRUCKNAV_ETS2_TRUCKNAV_DIR:-$REPO_ROOT/build/map-data/ets2-trucknav}"

REF_ETS2="$REFERENCE_REPO/public/data/ets2"
DEST_ETS2="$REPO_ROOT/public/data/ets2"
GEN_TILES="$GENERATED_ROOT/map-data/tiles"
GEN_ROUTING="$GENERATED_ROOT/roadnetwork"
GEN_SPRITES="$GENERATED_ROOT/sprites"

if [[ ! -f "$REF_ETS2/map-data/tiles/map-data-combined.mp3" ]]; then
    echo "Reference ETS2 static basemap not found at:" >&2
    echo "  $REF_ETS2" >&2
    echo "Set TRUCKNAV_REFERENCE_REPO to a TruckNav checkout with the legacy ETS2 map." >&2
    exit 2
fi

for required in     "$GEN_TILES/roads.mp3"     "$GEN_ROUTING/graph.bin"     "$GEN_ROUTING/geometry.bin"     "$GEN_ROUTING/nodes.bin"     "$GEN_ROUTING/trucknav-graph-manifest.json"     "$GENERATED_ROOT/map-data/trucknav-visual-manifest.json"     "$GENERATED_ROOT/map-data/trucknav-linux-map.json"     "$GENERATED_ROOT/map-data/cities.json"     "$GENERATED_ROOT/map-data/companies.geojson"     "$GEN_SPRITES/sprites.json"     "$GEN_SPRITES/sprites.png"     "$GEN_SPRITES/sprites@2x.json"     "$GEN_SPRITES/sprites@2x.png"
do
    if [[ ! -f "$required" ]]; then
        echo "Missing generated ETS2 asset: $required" >&2
        exit 3
    fi
done

echo "=== Preparing fresh ETS2 TruckNav bundle ==="
echo "Reference static basemap: $REFERENCE_REPO"
echo "Target:                   $REPO_ROOT"
echo

rm -rf "$DEST_ETS2"
mkdir -p "$REPO_ROOT/public/data"

# Preserve TruckNav's existing static combined background layer and auxiliary
# files, then replace every game-derived dynamic map/routing file with the
# freshly generated Europe data.
cp -a "$REF_ETS2" "$DEST_ETS2"

cp -f "$GEN_TILES/roads.mp3" "$DEST_ETS2/map-data/tiles/roads.mp3"
cp -f "$GENERATED_ROOT/map-data/trucknav-visual-manifest.json"     "$DEST_ETS2/map-data/trucknav-visual-manifest.json"
cp -f "$GENERATED_ROOT/map-data/trucknav-linux-map.json"     "$DEST_ETS2/map-data/trucknav-linux-map.json"
cp -f "$GENERATED_ROOT/map-data/cities.json"     "$DEST_ETS2/map-data/cities.json"
cp -f "$GENERATED_ROOT/map-data/companies.geojson"     "$DEST_ETS2/map-data/companies.geojson"

mkdir -p "$DEST_ETS2/roadnetwork"
cp -f "$GEN_ROUTING/graph.bin" "$DEST_ETS2/roadnetwork/graph.bin"
cp -f "$GEN_ROUTING/geometry.bin" "$DEST_ETS2/roadnetwork/geometry.bin"
cp -f "$GEN_ROUTING/nodes.bin" "$DEST_ETS2/roadnetwork/nodes.bin"
cp -f "$GEN_ROUTING/trucknav-graph-manifest.json"     "$DEST_ETS2/roadnetwork/trucknav-graph-manifest.json"

mkdir -p "$REPO_ROOT/public/sprites/ets2"
cp -f "$GEN_SPRITES/"sprites* "$REPO_ROOT/public/sprites/ets2/"

cat > "$DEST_ETS2/TRUCKNAV_TEST_BUILD.txt" <<EOF
ETS2 fresh Europe development bundle
Generated from local installed ETS2 data.
Fresh roads/map features: yes
Fresh routing graph: yes
Fresh sprites: yes
Static legacy combined basemap: copied from $REFERENCE_REPO
EOF

rm -f "$DEST_ETS2/TRUCKNAV_BUNDLED_MAP.txt"

echo "Fresh ETS2 bundle prepared."
echo "  $DEST_ETS2/map-data/tiles/roads.mp3"
echo "  $DEST_ETS2/roadnetwork/{graph.bin,geometry.bin,nodes.bin}"
echo "  $REPO_ROOT/public/sprites/ets2/"
