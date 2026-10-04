#!/usr/bin/env python3
import json
import sys
from collections import Counter
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: filter-ats-released-geojson.py <input.geojson> <output.geojson>")

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

data = json.loads(src.read_text(encoding="utf-8"))
features = data.get("features")
if not isinstance(features, list):
    raise SystemExit(f"{src} is not a GeoJSON FeatureCollection")

kept = []
skipped_guards = Counter()
skipped_types = Counter()

for feature in features:
    props = feature.get("properties") or {}
    guard = props.get("dlcGuard")

    # Released ATS map support in this branch is defined by guards 0..57.
    # South Dakota is 53 and its released-state border combinations are 54..57.
    # ATS 1.61 also contains later guard ids (observed: 59 and 65 in routing).
    # Do not ship those until their state/DLC meaning is known.
    if isinstance(guard, (int, float)) and guard > 57:
        guard_int = int(guard)
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

print(f"input features:  {len(features):,}")
print(f"kept features:   {len(kept):,}")
print(f"skipped features:{len(features) - len(kept):,}")
print("skipped guards:  ", dict(sorted(skipped_guards.items())))
print("skipped types:   ", dict(sorted(skipped_types.items())))
