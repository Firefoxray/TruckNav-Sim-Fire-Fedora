#!/usr/bin/env python3
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

if len(sys.argv) != 5:
    raise SystemExit(
        "usage: write-trucknav-linux-map-manifest.py "
        "<usa-version.txt> <graph-manifest.json> <visual-manifest.json> <output.json>"
    )

version_path = Path(sys.argv[1])
graph_path = Path(sys.argv[2])
visual_path = Path(sys.argv[3])
output_path = Path(sys.argv[4])

version = version_path.read_text(encoding="utf-8").strip()
graph = json.loads(graph_path.read_text(encoding="utf-8"))
visual = json.loads(visual_path.read_text(encoding="utf-8"))

manifest = {
    "schemaVersion": 1,
    "game": "ats",
    "gameVersion": version,
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "projection": graph.get("source", {}).get("projection")
    or visual.get("projection"),
    "supportedDlcs": 18,
    "newestDlc": "South Dakota",
    "southDakotaEdges": graph.get("dlcEncoding", {}).get("southDakotaEdges"),
    "graphEdges": graph.get("graph", {}).get("edges"),
    "graphNodes": graph.get("graph", {}).get("nodes"),
    "visualFeatures": visual.get("features"),
    "bounds": visual.get("bounds"),
    "skippedUnknownDlcGuards": graph.get("skippedUnknownDlcGuards", {}),
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(
    json.dumps(manifest, indent=2) + "\n",
    encoding="utf-8",
)

print(f"TruckNav Linux map manifest: {output_path}")
print(json.dumps(manifest, indent=2))
