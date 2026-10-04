# ATS map rebuild pipeline

This branch is for bringing the ATS map data up to the latest released map DLC
without modifying the working `master` branch.

## Current target

- Existing TruckNav data: through Illinois.
- New target: South Dakota.
- TruckNav internal DLC id planned for South Dakota: `18`.

## Source tooling

The rebuild work uses the GPL-3.0-or-later `truckermudgeon/maps`
parser/generator toolchain as the reproducible source for ATS map extraction.

Pinned source revision while this pipeline is being developed:

```
d56d0e3fb319230e84284f3029f8bda2c4b572a2
```

The upstream tool currently contains South Dakota DLC guard definitions
(53-57), but South Dakota is not yet included in its selectable-DLC set. The
TruckNav pipeline therefore must not assume that upstream graph generation is
South-Dakota-ready without verification.

## Step 1: preflight

From this repository run:

```bash
./scripts/map-data/ats-map-preflight.sh
```

If ATS is installed in a non-standard Steam library and the script cannot
choose it automatically:

```bash
TRUCKNAV_ATS_DIR="/path/to/American Truck Simulator" \\
  ./scripts/map-data/ats-map-preflight.sh
```

The script is read-only. It reports tool versions, locates the ATS Steam
manifest, validates the game directory, and lists installed map DLC archives.

## Planned pipeline

1. Parse the installed ATS game files.
2. Generate fresh ATS GeoJSON/PMTiles/sprites.
3. Generate or convert a directed routing graph.
4. Map SCS DLC guards to TruckNav DLC ownership ids.
5. Preserve route geometry through roads/prefabs.
6. Preserve turn and roundabout metadata where possible.
7. Package the generated map into the format consumed by TruckNav.
8. Run routing and DLC-gating validation before replacing the current map.

Do not publish SCS game archives or raw extracted game assets. Generated map
artifacts and source-derived metadata should be reviewed separately before
distribution.
