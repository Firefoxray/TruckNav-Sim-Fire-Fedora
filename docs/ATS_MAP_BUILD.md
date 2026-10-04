# ATS map rebuild pipeline

This branch is for bringing the ATS map data up to the latest released map DLC
without modifying the working `master` branch.

## Current target

- Existing TruckNav data: through Illinois.
- New target: South Dakota.
- TruckNav internal DLC id planned for South Dakota: `18`.
- SCS South Dakota archive confirmed on the development machine: `dlc_sd.scs`.

## Source tooling

The rebuild uses the GPL-3.0-or-later `truckermudgeon/maps`
parser/generator toolchain as the reproducible source for ATS map extraction.

Pinned source revision:

```
d56d0e3fb319230e84284f3029f8bda2c4b572a2
```

At that revision, upstream already defines South Dakota DLC guards `53-57`,
but intentionally excludes South Dakota from the selectable DLC set and does
not map `dlc_sd.scs`. TruckNav carries a small local patch for the build
tooling so we can parse the released DLC now without waiting for upstream.

The local patch does four things:

1. Makes South Dakota selectable in the ATS DLC set.
2. Adds the South Dakota display name.
3. Maps `dlc_sd.scs` to singleton DLC guard `53`.
4. Leaves the upstream checkout isolated under `.tools/map-data/`.

## Completed preflight

The Fedora desktop preflight found:

- ATS install:
  `~/.local/share/Steam/steamapps/common/American Truck Simulator`
- South Dakota:
  `dlc_sd.scs`
- System Node:
  `v22.23.1`

The upstream map tool currently requires Node >= 24.13.0. We do **not** replace
the system Node installation. `setup-map-tools.sh` downloads a private Node
24.13.0 runtime under `.tools/map-data/` and uses it only for this pipeline.

The parser reads `version.scs`; a loose `version.sii` in the ATS directory is
not required.

## Step 1: preflight

Read-only:

```bash
bash scripts/map-data/ats-map-preflight.sh
```

## Step 2: bootstrap parser/generator tooling

```bash
bash scripts/map-data/setup-map-tools.sh
```

This:

- downloads the isolated Node 24 runtime;
- clones the pinned `truckermudgeon/maps` revision;
- applies the South Dakota compatibility patch;
- installs npm dependencies;
- builds the native parser addon.

It does not modify ATS or Steam.

## Step 3: parse the installed ATS files

```bash
bash scripts/map-data/parse-ats.sh
```

Output is written to:

```
build/map-data/ats-parser/
```

The script validates that the parser produced roads with South Dakota DLC guard
`53` and prints any country entry that mentions Dakota, including its country
id. Keep the full terminal output for the next stage.

## Parser validation result

The ATS 1.61.3.1 parse completed successfully on the Fedora development
machine.

Validated South Dakota values:

- Country token: `south_dakota`
- Country id: `41`
- Singleton SCS DLC guard: `53`
- Parsed South Dakota cities: `13`
- Parsed South Dakota roads: `6059`

The build-tool patch now also maps country id `41` to DLC guard `53`.

## Step 4: generate map/routing source data

Pull the latest branch changes, rerun setup once so the updated compatibility
patch is applied to the isolated tooling checkout, then generate the source
artifacts:

```bash
git pull --ff-only
bash scripts/map-data/setup-map-tools.sh
bash scripts/map-data/generate-ats-source-data.sh
```

This stage intentionally does not require tippecanoe yet. It generates:

- normal ATS GeoJSON;
- uncoalesced ATS GeoJSON for matching routing edges to road geometry;
- the upstream directed routing graph;
- prefab curves;
- roundabout metadata;
- a fresh ATS sprite sheet.

Output is written under:

```
build/map-data/ats-generated/
```

## Next pipeline stages

After source-data generation:

1. Inspect/validate the generated South Dakota graph and geometry.
2. Convert the directed graph into TruckNav's binary graph format.
3. Generate PMTiles from the same parsed source.
4. Generate or adapt the combined visual map layers required by TruckNav.
4. Convert SCS DLC guards to TruckNav DLC ownership ids.
   - South Dakota singleton guard `53` -> TruckNav DLC id `18`.
   - Mixed border guards `54-57` must remain gated by all required states.
5. Preserve road/prefab route geometry.
6. Preserve turn and roundabout metadata where possible.
7. Package the output in TruckNav's downloadable ATS map format.
8. Run routing and DLC-gating validation.
9. Only after validation, wire South Dakota into the live TruckNav DLC UI.

Do not publish SCS game archives or raw extracted game assets. Generated map
artifacts and source-derived metadata should be reviewed separately before
distribution.


## Step 5: export TruckNav routing binaries

After `finish-ats-source-data.sh` completes:

```bash
git pull --ff-only
bash scripts/map-data/export-trucknav-routing.sh
```

This exporter uses the fresh upstream directed graph plus the parsed ATS map
geometry to write TruckNav's runtime format:

```
build/map-data/ats-trucknav/roadnetwork/
  graph.bin
  geometry.bin
  nodes.bin
  trucknav-graph-manifest.json
```

The exporter:

- remaps 64-bit SCS node UIDs to compact integer ids;
- reconstructs each edge's road/prefab geometry and projects it to WGS84;
- preserves edge distances and ferry flags;
- calculates arrival/departure headings;
- maps SCS DLC guards to TruckNav DLC ids;
- encodes multi-state border requirements as an exact Float32-safe bitmask;
- marks detected roundabout edges for a generic roundabout instruction;
- emits a manifest with South Dakota edge counts and build statistics.

Legacy TruckNav maps still use one DLC id in the same graph field. New values
at or above `1 << 20` represent a flagged DLC bitmask. Runtime routing on this
branch understands both formats.

Accurate roundabout exit ordinals are deliberately deferred. The generated
graph preserves routing through roundabouts and identifies them, but currently
uses TruckNav's generic "Take the exit at the roundabout" prompt for the new
graph. This can be enhanced after route validation.

## Remaining work

1. Validate generated binary routing inside TruckNav.
2. Generate PMTiles for roads and combined visual layers.
3. Filter or account for ATS 1.61's currently unknown guards 58, 59 and 65
   before packaging visual map data.
4. Package and host the ATS 1.61 map bundle.
5. Add South Dakota (TruckNav DLC id 18) to the live DLC UI only after the
   routing and visual map bundle both pass validation.


## Step 6: build fresh ATS visual PMTiles

The working TruckNav install still contains the legacy
`map-data-combined.mp3`, which is useful for static background geography
(water/state boundaries). The new ATS parser output is used for roads, map
areas, prefabs, labels and POIs.

Bootstrap an isolated Tippecanoe 2.79.0 build and generate the released-state
ATS PMTiles:

```bash
git pull --ff-only
bash scripts/map-data/setup-tippecanoe.sh
bash scripts/map-data/generate-ats-visual-map.sh
```

The visual builder filters any SCS DLC guard above 57 before tile generation.
For the ATS 1.61 source used during this project, routing observed unreleased
guards 59 and 65; they are intentionally excluded rather than guessed.

Output:

```
build/map-data/ats-trucknav/map-data/tiles/roads.mp3
build/map-data/ats-trucknav/sprites/
```

The generated `roads.mp3` is a full fresh ATS feature tileset with source
layer `ats`. The MapLibre code on this branch uses it for base-map roads,
prefabs, map areas, POIs, city labels and state-name points. The old
`map-data-combined.mp3` is retained only for static background layers such as
water and state outlines.

## Step 7: prepare an isolated test bundle

After routing and visual generation both pass:

```bash
bash scripts/map-data/prepare-ats-test-bundle.sh
```

By default this copies the auxiliary ATS data and static combined basemap from
the sibling working checkout:

```
../TruckNav-Sim-Fire-Fedora
```

Then it overwrites the South Dakota worktree with the fresh ATS 1.61 roads,
routing binaries and sprites. This keeps the normal working checkout untouched.

The test bundle is installed under:

```
public/data/ats/
public/sprites/ats/
```

If the reference checkout is elsewhere, set `TRUCKNAV_REFERENCE_REPO`.
