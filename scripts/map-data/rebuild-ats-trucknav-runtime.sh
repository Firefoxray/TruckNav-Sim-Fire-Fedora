#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

echo "=== Rebuilding TruckNav ATS runtime assets ==="
echo
bash scripts/map-data/export-trucknav-routing.sh

echo
bash scripts/map-data/generate-ats-visual-map.sh

echo
echo "=== Generating current ATS city/company data ==="
python3 scripts/map-data/generate-ats-aux-data.py \
  build/map-data/ats-parser/usa-cities.json \
  build/map-data/ats-trucknav/map-data/ats-released.geojson \
  build/map-data/ats-trucknav/map-data

echo
echo "=== Writing TruckNav Linux map manifest ==="
python3 scripts/map-data/write-trucknav-linux-map-manifest.py \
  build/map-data/ats-parser/usa-version.txt \
  build/map-data/ats-trucknav/roadnetwork/trucknav-graph-manifest.json \
  build/map-data/ats-trucknav/map-data/trucknav-visual-manifest.json \
  build/map-data/ats-trucknav/map-data/trucknav-linux-map.json

echo
bash scripts/map-data/prepare-ats-test-bundle.sh

echo
echo "=== ATS runtime rebuild complete ==="
echo "Restart TruckNav before testing so the browser reloads the new PMTiles and routing binaries."
