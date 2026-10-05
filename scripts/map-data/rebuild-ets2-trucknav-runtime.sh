#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

echo "=== Full TruckNav ETS2 Europe rebuild ==="
echo "This parses the installed game and can take a while."
echo

echo "[1/7] Preparing map tooling..."
bash scripts/map-data/setup-map-tools.sh

echo
echo "[2/7] Parsing installed ETS2 files..."
bash scripts/map-data/parse-ets2.sh

echo
echo "[3/7] Generating Europe map/graph source data..."
bash scripts/map-data/generate-ets2-source-data.sh

echo
echo "[4/7] Exporting TruckNav routing binaries..."
bash scripts/map-data/export-ets2-trucknav-routing.sh

echo
echo "[5/7] Building TruckNav ETS2 visual map..."
bash scripts/map-data/generate-ets2-visual-map.sh

echo
echo "[6/7] Generating current ETS2 city/company data..."
python3 scripts/map-data/generate-ets2-aux-data.py   build/map-data/ets2-parser/europe-cities.json   build/map-data/ets2-trucknav/map-data/ets2-released.geojson   build/map-data/ets2-trucknav/map-data

echo
echo "Writing TruckNav Linux ETS2 map manifest..."
python3 scripts/map-data/write-trucknav-linux-map-manifest.py   ets2   build/map-data/ets2-parser/europe-version.txt   build/map-data/ets2-trucknav/roadnetwork/trucknav-graph-manifest.json   build/map-data/ets2-trucknav/map-data/trucknav-visual-manifest.json   build/map-data/ets2-trucknav/map-data/trucknav-linux-map.json

echo
echo "[7/7] Installing fresh ETS2 runtime bundle..."
bash scripts/map-data/prepare-ets2-test-bundle.sh

echo
echo "=== ETS2 Europe rebuild complete ==="
echo "Restart/reload TruckNav before testing the fresh map."
