#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REFERENCE_REPO="${TRUCKNAV_REFERENCE_REPO:-$(dirname "$REPO_ROOT")/TruckNav-Sim-Fire-Fedora}"
GENERATED_ROOT="${TRUCKNAV_ATS_TRUCKNAV_DIR:-$REPO_ROOT/build/map-data/ats-trucknav}"

REF_ATS="$REFERENCE_REPO/public/data/ats"
DEST_ATS="$REPO_ROOT/public/data/ats"
GEN_TILES="$GENERATED_ROOT/map-data/tiles"
GEN_ROUTING="$GENERATED_ROOT/roadnetwork"
GEN_SPRITES="$GENERATED_ROOT/sprites"

if [[ ! -f "$REF_ATS/map-data/tiles/map-data-combined.mp3" ]]; then
    echo "Reference ATS map data not found at:" >&2
    echo "  $REF_ATS" >&2
    echo "Set TRUCKNAV_REFERENCE_REPO to your working TruckNav repo." >&2
    exit 2
fi

for required in     "$GEN_TILES/roads.mp3"     "$GEN_ROUTING/graph.bin"     "$GEN_ROUTING/geometry.bin"     "$GEN_ROUTING/nodes.bin"     "$GEN_ROUTING/trucknav-graph-manifest.json"     "$GEN_SPRITES/sprites.json"     "$GEN_SPRITES/sprites.png"     "$GEN_SPRITES/sprites@2x.json"     "$GEN_SPRITES/sprites@2x.png"
do
    if [[ ! -f "$required" ]]; then
        echo "Missing generated test asset: $required" >&2
        exit 3
    fi
done

echo "=== Preparing isolated South Dakota test bundle ==="
echo "Reference: $REFERENCE_REPO"
echo "Target:    $REPO_ROOT"
echo

rm -rf "$DEST_ATS"
mkdir -p "$REPO_ROOT/public/data"

# Keep the existing TruckNav auxiliary ATS files and static combined basemap.
cp -a "$REF_ATS" "$DEST_ATS"

# Replace dynamic roads/map features and routing with the fresh ATS 1.61 build.
cp -f "$GEN_TILES/roads.mp3" "$DEST_ATS/map-data/tiles/roads.mp3"
cp -f \
    "$GENERATED_ROOT/map-data/trucknav-visual-manifest.json" \
    "$DEST_ATS/map-data/trucknav-visual-manifest.json"
cp -f "$GENERATED_ROOT/map-data/cities.json" "$DEST_ATS/map-data/cities.json"
cp -f \
    "$GENERATED_ROOT/map-data/companies.geojson" \
    "$DEST_ATS/map-data/companies.geojson"
mkdir -p "$DEST_ATS/roadnetwork"
cp -f "$GEN_ROUTING/graph.bin" "$DEST_ATS/roadnetwork/graph.bin"
cp -f "$GEN_ROUTING/geometry.bin" "$DEST_ATS/roadnetwork/geometry.bin"
cp -f "$GEN_ROUTING/nodes.bin" "$DEST_ATS/roadnetwork/nodes.bin"
cp -f     "$GEN_ROUTING/trucknav-graph-manifest.json"     "$DEST_ATS/roadnetwork/trucknav-graph-manifest.json"

mkdir -p "$REPO_ROOT/public/sprites/ats"
cp -f "$GEN_SPRITES/"sprites* "$REPO_ROOT/public/sprites/ats/"

cat > "$DEST_ATS/TRUCKNAV_TEST_BUILD.txt" <<EOF
ATS 1.61 South Dakota development bundle
Generated from local installed ATS data.
Fresh roads/map features: yes
Fresh routing graph: yes
Fresh sprites: yes
Static legacy combined basemap: copied from $REFERENCE_REPO
EOF

echo "Test bundle prepared."
echo
echo "Fresh:"
echo "  $DEST_ATS/map-data/tiles/roads.mp3"
echo "  $DEST_ATS/roadnetwork/{graph.bin,geometry.bin,nodes.bin}"
echo "  $REPO_ROOT/public/sprites/ats/"
echo
echo "Reused only for static background layers:"
echo "  $DEST_ATS/map-data/tiles/map-data-combined.mp3"
