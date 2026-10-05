#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_ROOT="${TRUCKNAV_MAP_TOOLS_ROOT:-$REPO_ROOT/.tools/map-data}"
TIP_BIN="$TOOLS_ROOT/tippecanoe/bin"
SRC_GEOJSON="${TRUCKNAV_ETS2_GEOJSON:-$REPO_ROOT/build/map-data/ets2-generated/map/ets2.geojson}"
OUT_ROOT="${TRUCKNAV_ETS2_TRUCKNAV_DIR:-$REPO_ROOT/build/map-data/ets2-trucknav}"
FILTERED_WGS84="$OUT_ROOT/map-data/ets2-released-wgs84.geojson"
FILTERED_GEOJSON="$OUT_ROOT/map-data/ets2-released.geojson"
TILES_DIR="$OUT_ROOT/map-data/tiles"
SPRITES_SRC="$REPO_ROOT/build/map-data/ets2-generated/sprites"
SPRITES_DST="$OUT_ROOT/sprites"

if [[ ! -f "$SRC_GEOJSON" ]]; then
    echo "Missing generated ETS2 GeoJSON: $SRC_GEOJSON" >&2
    echo "Run the ETS2 source-data generator first." >&2
    exit 2
fi

if [[ ! -f "$TOOLS_ROOT/env.sh" ]]; then
    echo "Map tooling is not bootstrapped. Run:" >&2
    echo "  bash scripts/map-data/setup-map-tools.sh" >&2
    exit 3
fi

# shellcheck disable=SC1090
source "$TOOLS_ROOT/env.sh"

if [[ ! -x "$TIP_BIN/tippecanoe" ]]; then
    bash "$REPO_ROOT/scripts/map-data/setup-tippecanoe.sh"
fi

mkdir -p "$TILES_DIR" "$SPRITES_DST"

echo "=== Filtering unsupported/unreleased ETS2 guard data ==="
python3 "$REPO_ROOT/scripts/map-data/filter-ets2-released-geojson.py"     "$SRC_GEOJSON"     "$FILTERED_WGS84"

echo
echo "=== Reprojecting ETS2 visual data into TruckNav coordinate space ==="
REPROJECT_SRC="$REPO_ROOT/scripts/map-data/trucknav-reproject-geojson.ts"
REPROJECT_DST="$TRUCKNAV_MAPS_DIR/packages/clis/generator/trucknav-reproject-geojson.ts"
cp "$REPROJECT_SRC" "$REPROJECT_DST"
(
    cd "$TRUCKNAV_MAPS_DIR"
    ./node_modules/.bin/tsx         "$REPROJECT_DST"         europe         "$FILTERED_WGS84"         "$FILTERED_GEOJSON"
)

TMP_PM="$OUT_ROOT/map-data/ets2.pmtiles"
OUT_PM="$TILES_DIR/roads.mp3"
rm -f "$TMP_PM"

echo
echo "=== Building TruckNav ETS2 visual PMTiles ==="
"$TIP_BIN/tippecanoe"     -Z4     -z13     -B4     -b10     --force     -l ets2     -y type     -y dlcGuard     -y zIndex     -y height     -y hidden     -y secret     -y poiType     -y poiName     -y sprite     -y scaleRank     -y capital     -y roadType     -y color     -y name     -o "$TMP_PM"     "$FILTERED_GEOJSON"

mv -f "$TMP_PM" "$OUT_PM"

for f in sprites.json sprites.png sprites@2x.json sprites@2x.png; do
    if [[ ! -f "$SPRITES_SRC/$f" ]]; then
        echo "Missing generated sprite file: $SPRITES_SRC/$f" >&2
        exit 3
    fi
    cp -f "$SPRITES_SRC/$f" "$SPRITES_DST/$f"
done

echo
echo "=== ETS2 visual-map sanity check ==="
python3 - "$OUT_PM" "$FILTERED_GEOJSON" <<'PY'
import json
import sys
from pathlib import Path

pm = Path(sys.argv[1])
geojson = Path(sys.argv[2])

magic = pm.read_bytes()[:7]
if magic != b"PMTiles":
    raise SystemExit(f"bad PMTiles magic: {magic!r}")

data = json.loads(geojson.read_text(encoding="utf-8"))
types = {}
nordic = 0
for feature in data.get("features", []):
    props = feature.get("properties") or {}
    t = str(props.get("type", "<missing>"))
    types[t] = types.get(t, 0) + 1
    if props.get("dlcGuard") in (23, 24, 25):
        nordic += 1

if nordic <= 0:
    raise SystemExit("no Nordic Horizons visual features were preserved")

print(f"PMTiles size:           {pm.stat().st_size / 1024 / 1024:.2f} MiB")
print(f"visual features:        {len(data.get('features', [])):,}")
print(f"Nordic Horizon features:{nordic:,}")
print("feature types:")
for key in sorted(types):
    print(f"  {key:12s} {types[key]:,}")
print("TruckNav ETS2 visual-map sanity check: OK")
PY

echo
echo "Fresh ETS2 visual map is ready:"
echo "  $OUT_PM"
echo "Fresh ETS2 sprite sheet:"
echo "  $SPRITES_DST"
