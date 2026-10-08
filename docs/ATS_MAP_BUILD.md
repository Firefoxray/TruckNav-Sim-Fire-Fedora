# ATS map rebuild pipeline

TruckNav Linux can rebuild its American Truck Simulator map data directly from
the locally installed game files.

The current pipeline has been validated against ATS 1.61.x and supports the
released ATS map-DLC set through South Dakota.

## What the rebuild produces

The pipeline generates:

- parsed ATS map data from the installed `.scs` archives;
- a directed routing graph;
- TruckNav `graph.bin`, `geometry.bin`, and `nodes.bin`;
- fresh visual PMTiles;
- a fresh ATS sprite sheet;
- cities and company POIs;
- a TruckNav Linux map manifest with the source game version and Steam build.

Generated runtime data is installed under:

```
public/data/ats/
public/sprites/ats/
```

Build/intermediate data stays under:

```
build/map-data/
.tools/map-data/
```

and is not intended for source control.

## One-command rebuild

From the repository root:

```bash
bash scripts/map-data/rebuild-ats-trucknav-runtime.sh
```

The TruckNav Linux web control center uses the same rebuild script.

## Tooling

The rebuild uses a pinned revision of
[truckermudgeon/maps](https://github.com/truckermudgeon/maps):

```
d56d0e3fb319230e84284f3029f8bda2c4b572a2
```

`scripts/map-data/setup-map-tools.sh` keeps this tooling isolated under
`.tools/map-data/`, downloads a private Node 24.13.0 runtime, initializes the
required submodules, and applies TruckNav's compatibility patch:

```
scripts/map-data/patch-trucksim-maps.py
```

That patch currently carries compatibility needed by the released ATS/ETS2
1.61 game data, including South Dakota support and newer parser/texture cases.
It does not modify the installed game.

## Pipeline stages

For debugging or development, the rebuild can be run stage-by-stage:

```bash
bash scripts/map-data/setup-map-tools.sh
bash scripts/map-data/parse-ats.sh
bash scripts/map-data/generate-ats-source-data.sh
bash scripts/map-data/export-trucknav-routing.sh
bash scripts/map-data/setup-tippecanoe.sh
bash scripts/map-data/generate-ats-visual-map.sh
```

The final runtime/manifest packaging is handled by
`rebuild-ats-trucknav-runtime.sh`.

## DLC routing

TruckNav keeps its legacy single-DLC graph value for roads that require one
expansion and uses a Float32-safe flagged bitmask for roads that require
multiple map DLCs at borders.

For ATS, TruckNav's map-DLC IDs currently run through:

```
18 = South Dakota
```

Unknown or unreleased SCS DLC guards are skipped rather than guessed.

## Visual map

Fresh generated `roads.mp3` data is used for roads, map areas, prefabs, POIs,
cities, and state-name features. The legacy combined PMTiles file remains
useful for static background geography such as water and state/country
boundaries.

## Actual game-derived elevation relief (optional)

The normal ATS map build provides roads, service areas and city labels, but
it does **not** generate hills or mountains. The Terrain map style therefore
remains a simple green land palette until an optional elevation asset exists.

The pinned `truckermudgeon/maps` toolkit can build colored elevation
polygons from SCS game's parsed `usa-elevation.json` samples. No satellite
imagery or real-world elevation data is overlaid, so game coordinates stay
aligned with the TruckNav road graph.

Once after an ATS parser/build:

```bash
cd ~/Projects/TruckNav-Sim-South-Dakota
bash scripts/map-data/build-ats-elevation.sh
```

This may be CPU/RAM intensive. The script requires
`build/map-data/ats-parser/usa-elevation.json` and the existing map-tool
setup; if either is absent it stops and tells you what is missing. It
builds and reprojects contour polygons into TruckNav's custom coordinate
system, packages them as PMTiles, and installs only:

```
public/data/ats/map-data/tiles/terrain.mp3
```

Reload TruckNav and choose the **Terrain** style. Elevation colors follow
the game-generated relief, and hide again when switching back to the
TruckNav or Minimal styles. The usual updater does not generate terrain:
it only updates source code. If this optional file is missing, the app
falls back to its normal map without an error.

The height polygons are *game-derived interpolations*, not a surveyed
digital elevation model. They do not provide detailed hillshade,
contour isolines, 3D mountains, local lake outlines, or accurate
real-world coastlines. Those require a separate and validated terrain /
hydrography data source and projection work.

## Validation

The generated routing exporter performs binary-size and graph sanity checks.
The visual pipeline validates the PMTiles header and confirms current-DLC
features are present before packaging.

Do not redistribute SCS game archives or raw extracted game files. The rebuild
is intended to run against a user's own local ATS installation.
