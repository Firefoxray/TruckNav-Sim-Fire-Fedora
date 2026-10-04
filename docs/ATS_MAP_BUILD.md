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
