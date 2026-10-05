# TruckNav Linux

TruckNav Linux is the Linux-focused fork of TruckNav. It keeps the original
TruckNav navigation UI and project lineage while adding a native Linux workflow
for ATS, local map generation, and self-update support.

## Local control center

When TruckNav is opened locally on Linux at `127.0.0.1` or `localhost`, the
game manager shows a TruckNav Linux control center with:

- current Git branch and commit;
- source/update status;
- locally generated ATS map version;
- newest supported ATS DLC;
- **Check for Updates**;
- **Update TruckNav**;
- **Rebuild ATS Map**.

Maintenance actions are accepted only from loopback requests. A browser opened
from another machine on the LAN can view TruckNav, but cannot trigger update or
map rebuild commands.

## App updates

The control center calls the local updater:

```bash
scripts/linux/update-trucknav-linux.sh
```

The updater:

1. refuses to overwrite tracked source changes;
2. fetches the configured upstream branch;
3. fast-forwards only (no automatic conflict resolution);
4. refreshes `node_modules` only when package metadata changed;
5. runs a production Nuxt build as validation.

Generated ATS runtime data is intentionally ignored by the source dirty check.

## ATS map updates

**Rebuild ATS Map** runs:

```bash
scripts/map-data/rebuild-ats-trucknav-runtime.sh
```

against the installed ATS files. It regenerates routing, PMTiles, sprites,
cities, companies, and the TruckNav Linux map manifest. ATS itself can remain
running while TruckNav is rebuilt; restart ATS only when the telemetry plugin
DLL itself changes.

The generated runtime manifest is:

```
public/data/ats/map-data/trucknav-linux-map.json
```

and includes the ATS version, supported DLC count, projection, graph metadata,
visual bounds, and generation timestamp.

## Launch behavior

`scripts/linux/launch-ats-trucknav.sh` reuses an already running ATS process.
It starts the TruckNav web app, waits until ATS is available, then starts the
telemetry helper. This allows UI/map development without repeatedly restarting
the game.


## Stable and Testing channels

The Fedora desktop launcher is channel-aware. It keeps two repository paths in:

```
~/.config/trucknav-linux-launcher/config.json
```

The intended layout during development is:

```
Stable  -> TruckNav-Sim-Fire-Fedora       (master)
Testing -> TruckNav-Sim-South-Dakota      (development worktree)
```

The application-menu shortcuts resolve the active channel at launch time, so
they do not need to be recreated whenever the active checkout changes. The GUI
launcher shows **Stable** and **Testing** buttons and restarts itself after a
channel switch.

Install/refresh the channel-aware shortcuts from a checkout with:

```bash
bash scripts/linux/install-desktop-files.sh --activate testing
```

or:

```bash
bash scripts/linux/install-desktop-files.sh --activate stable
```

The launcher UI and icon are copied under `~/.local/share/trucknav-linux/` so
the channel switcher remains available even if the active checkout itself is an
older stable revision.

When a tested feature branch is merged into master, activate **Stable** and the
normal application-menu shortcuts immediately start using the master checkout.
The old Testing worktree can then be removed after it is no longer needed.


## Launcher development workflow

The Tk launcher keeps the common controls in a compact 3×2 grid. **Update
TruckNav** lives beside the Stable/Testing channel controls because updating the
application is independent of either truck game.

- **Update TruckNav** fetches/fast-forwards the active Stable or Testing
  checkout, validates it with a Nuxt production build, and refreshes the
  installed launcher/desktop files. It does not launch ATS or ETS2.
- **Launch TruckNav** starts the web application plus the telemetry helper but
  does not automatically start ATS.
- **Launch ATS + TruckNav together** starts ATS when needed and then starts the
  telemetry helper after the game is detected.

A separate `launch-web-only.sh` helper remains available for development from
the terminal, but it is intentionally not exposed as a large launcher button.
