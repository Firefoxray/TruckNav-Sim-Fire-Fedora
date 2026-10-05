#!/usr/bin/env python3
import json
import sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit(
        "usage: generate-ets2-aux-data.py <europe-cities.json> "
        "<trucknav-visual.geojson> <output-map-data-dir>"
    )

cities_src = Path(sys.argv[1])
visual_src = Path(sys.argv[2])
out_dir = Path(sys.argv[3])
out_dir.mkdir(parents=True, exist_ok=True)

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

cities = json.loads(cities_src.read_text(encoding="utf-8"))
if not isinstance(cities, list):
    raise SystemExit("europe-cities.json is expected to be a JSON array")

released_cities = []
for city in cities:
    guard = city.get("dlcGuard")
    if isinstance(guard, (int, float)) and int(guard) not in SUPPORTED_GUARDS:
        continue
    released_cities.append(city)

visual = json.loads(visual_src.read_text(encoding="utf-8"))
features = visual.get("features")
if not isinstance(features, list):
    raise SystemExit("visual GeoJSON is expected to be a FeatureCollection")

companies = []
for feature in features:
    props = feature.get("properties") or {}
    if props.get("type") == "poi" and props.get("poiType") == "company":
        companies.append(feature)

(out_dir / "cities.json").write_text(
    json.dumps(released_cities, separators=(",", ":"), ensure_ascii=False),
    encoding="utf-8",
)
(out_dir / "companies.geojson").write_text(
    json.dumps(
        {
            "type": "FeatureCollection",
            "name": "ets2",
            "features": companies,
        },
        separators=(",", ":"),
        ensure_ascii=False,
    ),
    encoding="utf-8",
)

print(f"released cities: {len(released_cities):,}")
print(f"company POIs:    {len(companies):,}")
print(f"wrote: {out_dir / 'cities.json'}")
print(f"wrote: {out_dir / 'companies.geojson'}")
