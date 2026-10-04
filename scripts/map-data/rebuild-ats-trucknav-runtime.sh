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
bash scripts/map-data/prepare-ats-test-bundle.sh

echo
echo "=== ATS runtime rebuild complete ==="
echo "Restart TruckNav before testing so the browser reloads the new PMTiles and routing binaries."
