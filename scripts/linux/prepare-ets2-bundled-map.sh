#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REFERENCE_REPO="${TRUCKNAV_REFERENCE_REPO:-$(dirname "$REPO_ROOT")/TruckNav-Sim-Fire-Fedora}"
SOURCE="$REFERENCE_REPO/public/data/ets2"
DEST="$REPO_ROOT/public/data/ets2"
SPRITE_SOURCE="$REFERENCE_REPO/public/sprites/ets2"
SPRITE_DEST="$REPO_ROOT/public/sprites/ets2"

required=(
  "map-data/tiles/roads.mp3"
  "map-data/tiles/map-data-combined.mp3"
  "roadnetwork/graph.bin"
  "roadnetwork/geometry.bin"
)

if [[ "$REFERENCE_REPO" == "$REPO_ROOT" ]]; then
  SOURCE="$DEST"
  SPRITE_SOURCE="$SPRITE_DEST"
fi

for rel in "${required[@]}"; do
  if [[ ! -f "$SOURCE/$rel" ]]; then
    echo "ETS2 bundled map asset not found: $SOURCE/$rel" >&2
    echo "The quick ETS2 path expects the older TruckNav ETS2 bundle in:" >&2
    echo "  $REFERENCE_REPO/public/data/ets2" >&2
    exit 2
  fi
done

if [[ "$SOURCE" != "$DEST" ]]; then
  echo "Copying bundled ETS2 map from:"
  echo "  $SOURCE"
  echo "to:"
  echo "  $DEST"
  rm -rf "$DEST"
  mkdir -p "$(dirname "$DEST")"
  cp -a "$SOURCE" "$DEST"
fi

if [[ -d "$SPRITE_SOURCE" && "$SPRITE_SOURCE" != "$SPRITE_DEST" ]]; then
  rm -rf "$SPRITE_DEST"
  mkdir -p "$(dirname "$SPRITE_DEST")"
  cp -a "$SPRITE_SOURCE" "$SPRITE_DEST"
fi

cat > "$DEST/TRUCKNAV_BUNDLED_MAP.txt" <<EOF
TruckNav Linux bundled ETS2 compatibility map
Source checkout: $REFERENCE_REPO
This is the existing TruckNav ETS2 map bundle, not a freshly regenerated map.
EOF

echo "ETS2 bundled map is ready:"
echo "  $DEST"
