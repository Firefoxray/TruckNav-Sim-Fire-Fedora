#!/usr/bin/env python3
import json
import sys
from collections import Counter
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit(
        "usage: filter-ets2-released-geojson.py <input.geojson> <output.geojson>"
    )

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

data = json.loads(src.read_text(encoding="utf-8"))
features = data.get("features")
if not isinstance(features, list):
    raise SystemExit(f"{src} is not a GeoJSON FeatureCollection")

# Supported released map-expansion guards in the pinned generator:
# 0 base
# 1..12 through Iberia
# 16..18 West Balkans (+ border composites)
# 20..22 Greece (+ border composites)
# 23..25 Nordic Horizons (+ border composites)
#
# Excluded:
# 13/14 Heart of Russia (unreleased)
# 15 Krone factory trailer-DLC content
# 19 Feldbinder factory trailer-DLC content
SUPPORTED_GUARDS = {
    *range(0, 13),
    16,
    17,
    18,
    20,
    21,
    22,
    23,
    24,
    25,
}

kept = []
skipped_guards = Counter()
skipped_types = Counter()

for feature in features:
    props = feature.get("properties") or {}
    guard = props.get("dlcGuard")

    if isinstance(guard, (int, float)):
        guard_int = int(guard)
        if guard_int not in SUPPORTED_GUARDS:
            skipped_guards[guard_int] += 1
            skipped_types[str(props.get("type", "<missing>"))] += 1
            continue

    kept.append(feature)

out = dict(data)
out["features"] = kept

dst.parent.mkdir(parents=True, exist_ok=True)
dst.write_text(
    json.dumps(out, separators=(",", ":"), ensure_ascii=False),
    encoding="utf-8",
)

print(f"input features:   {len(features):,}")
print(f"kept features:    {len(kept):,}")
print(f"skipped features: {len(features) - len(kept):,}")
print("skipped guards:   ", dict(sorted(skipped_guards.items())))
print("skipped types:    ", dict(sorted(skipped_types.items())))
