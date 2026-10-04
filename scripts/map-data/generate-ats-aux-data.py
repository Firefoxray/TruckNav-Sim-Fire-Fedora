#!/usr/bin/env python3
import json
import sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit(
        "usage: generate-ats-aux-data.py <usa-cities.json> "
        "<trucknav-visual.geojson> <output-map-data-dir>"
    )

cities_src = Path(sys.argv[1])
visual_src = Path(sys.argv[2])
out_dir = Path(sys.argv[3])
out_dir.mkdir(parents=True, exist_ok=True)

cities = json.loads(cities_src.read_text(encoding="utf-8"))
if not isinstance(cities, list):
    raise SystemExit("usa-cities.json is expected to be a JSON array")

released_cities = []
for city in cities:
    guard = city.get("dlcGuard")
    if isinstance(guard, (int, float)) and guard > 57:
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
            "name": "ats",
            "features": companies,
        },
        separators=(",", ":"),
        ensure_ascii=False,
    ),
    encoding="utf-8",
)

sd_cities = sum(
    1
    for city in released_cities
    if str(city.get("countryToken", "")).lower() == "south_dakota"
)
sd_companies = sum(
    1
    for feature in companies
    if (feature.get("properties") or {}).get("dlcGuard") in (53, 54, 55, 56, 57)
)

print(f"released cities:       {len(released_cities):,}")
print(f"South Dakota cities:   {sd_cities:,}")
print(f"company POIs:          {len(companies):,}")
print(f"South Dakota companies:{sd_companies:,}")
print(f"wrote: {out_dir / 'cities.json'}")
print(f"wrote: {out_dir / 'companies.geojson'}")
