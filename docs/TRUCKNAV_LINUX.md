# TruckNav Linux

TruckNav Linux is the Linux-focused fork of TruckNav. It keeps the original
TruckNav navigation UI and project lineage while adding a Fedora/Linux launcher,
local ATS/ETS2 map generation, shared browser settings, and Linux-friendly
telemetry handling.

## Linux launcher

The launcher provides:

- ATS / ETS2 selection;
- Stable / Testing channels;
- Launch TruckNav;
- Launch the selected game + TruckNav;
- Stop TruckNav;
- Open TruckNav in a browser;
- dependency/status checks;
- installer/repair actions;
- TruckNav self-update.

The selected game and launcher preferences are stored under:

```
~/.config/trucknav-linux-launcher/
```

The launcher version comes from the repository-root `VERSION` file. A checkout
on `master` is displayed as **Stable**; development branches are displayed as
**Testing**.

## Stable and Testing channels

The launcher can keep two local checkouts:

```text
Stable  -> master
Testing -> any development worktree/branch
```

The Testing checkout does not need a particular branch or directory name.

Install or refresh desktop integration with:

```bash
bash scripts/linux/install-desktop-files.sh --activate stable
```

or:

```bash
bash scripts/linux/install-desktop-files.sh --activate testing
```

## Telemetry

ATS uses Steam app id `270880`; ETS2 uses `227300`.

TruckNav Linux installs `electron/bin/scs-telemetry.dll` into the selected
game's `bin/win_x64/plugins/` directory when needed and starts
`TruckNavTelemetry.exe` through the matching Proton prefix.

The browser does not connect directly to port 30001. Nitro connects to the
local helper and exposes telemetry through the same TruckNav web origin, which
allows localhost, LAN browsers, and local reverse-proxy hostnames to use the
same live data without exposing the telemetry socket directly.

The combined game launcher avoids starting the telemetry Proton process while
Steam is still bootstrapping the game. Once the real game process exists,
telemetry starts immediately; there is no fixed post-launch wait.

## Web control center

The Linux web control center shows:

- branch / version information;
- update state;
- map version and Steam-build tracking;
- TruckNav update controls;
- ATS / ETS2 map rebuild controls;
- maintenance-job output.

Shared administration is enabled by default for browsers that can reach this
personal TruckNav instance. To make remote browsers view-only:

```bash
TRUCKNAV_SHARED_ADMIN=0
```

Do not expose the service to an untrusted public network with shared
administration enabled.

## Shared settings

Normal TruckNav preferences are stored on the host and synchronized across
browsers. Route destination state remains per-browser so one client does not
fight another client's active route.

## ATS map rebuild

Run:

```bash
bash scripts/map-data/rebuild-ats-trucknav-runtime.sh
```

See [ATS_MAP_BUILD.md](ATS_MAP_BUILD.md) for details.

## ETS2 map rebuild

TruckNav Linux also includes a Europe rebuild pipeline:

```bash
bash scripts/map-data/rebuild-ets2-trucknav-runtime.sh
```

The parser/export/visual stages have been validated on current ETS2 1.61 data.
The ETS2 in-game path is newer than the ATS path, so the existing bundled ETS2
map remains available as a fallback until the fresh runtime has been tested on
a given installation.

If the heavy parser/source stages have already completed, the final packaging
can be resumed without parsing Europe again:

```bash
bash scripts/map-data/finish-ets2-trucknav-runtime.sh
```

## Updating the fork

`scripts/linux/update-trucknav-linux.sh`:

1. refuses to overwrite tracked source changes;
2. fetches the configured upstream branch;
3. fast-forwards only;
4. refreshes dependencies when package metadata changes;
5. runs a production Nuxt build as validation;
6. refreshes the installed launcher/desktop integration.

Generated map/runtime data is excluded from the source-dirty check.

## Development helpers

UI only:

```bash
bash scripts/linux/launch-web-only.sh
```

TruckNav + telemetry:

```bash
bash scripts/linux/launch-trucknav.sh ats
bash scripts/linux/launch-trucknav.sh ets2
```

Game + TruckNav:

```bash
bash scripts/linux/launch-game-trucknav.sh ats
bash scripts/linux/launch-game-trucknav.sh ets2
```
