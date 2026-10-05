# TruckNav Linux

**TruckNav Linux** is my Fedora/Linux-focused fork of [TruckNav](https://github.com/Rares-Muntean/TruckNav-Sim), an external GPS/navigation app for **American Truck Simulator** and **Euro Truck Simulator 2**.

The goal of this fork is simple: make TruckNav work cleanly on Linux, keep the map data maintainable as SCS updates the games, and make normal use possible from a launcher instead of a pile of terminal commands.

## Current status

- **Primary platform:** Fedora Linux / KDE
- **Primary game:** American Truck Simulator through Steam + Proton
- **ATS map pipeline:** generated locally from installed game files
- **Current ATS coverage:** South Dakota and the currently supported released ATS DLC set
- **Telemetry:** relayed through the TruckNav server so localhost, LAN devices, and a local reverse-proxy hostname can use the same live data
- **ETS2:** the upstream UI/data support is still present, but the Linux map-generation/launcher pipeline has not been finished or tested yet
- **Map mods:** not currently supported

The fork version is tracked in [`VERSION`](VERSION).

## TruckNav Linux Launcher

The Linux launcher is the main control panel for this fork. It supports Stable/Testing channels, updates, dependency checks, ATS launch/monitoring, telemetry startup, browser launch, and clean shutdown.

> Screenshot: add `docs/images/trucknav-linux-launcher.png` to this repo and it will be shown here.

<!--
<p align="center">
  <img src="docs/images/trucknav-linux-launcher.png" alt="TruckNav Linux Launcher" width="720">
</p>
-->

## What this fork adds

- Native **TruckNav Linux Launcher**
- **Stable / Testing** launcher channels
- One-click **Update TruckNav**
- One-click **Rebuild ATS Map**
- Automatic ATS Steam-build vs. map-build tracking
- Current ATS routing/map generation from installed game files
- Shared settings across browsers on the TruckNav instance
- Same-origin telemetry relay for LAN/browser access
- South Dakota routing and visual map support
- North-up navigation follow that preserves manual map rotation
- Intermediate route stops with distance and ETA in addition to total trip distance/ETA

## Install on Fedora

Install the basic dependencies:

```bash
sudo dnf install -y nodejs npm git protontricks kde-cli-tools konsole python3 python3-tkinter curl procps-ng
```

Clone the repo and run the installer:

```bash
git clone https://github.com/Firefoxray/TruckNav-Sim-Fire-Fedora.git
cd TruckNav-Sim-Fire-Fedora
bash scripts/install-fedora.sh
```

After setup, open **TruckNav Linux Launcher** from the KDE application menu.

## Normal use

- **Launch TruckNav** — starts TruckNav and the telemetry helper without launching ATS.
- **Launch ATS + TruckNav together** — launches ATS if needed, waits for it, then starts telemetry.
- **Stop TruckNav** — stops the TruckNav web app and telemetry helper.
- **Open TruckNav in browser** — opens the local web UI.
- **Update TruckNav** — updates the active Stable/Testing checkout without starting a game.
- **Check dependencies/status** — checks the Linux setup.
- **Install/repair Fedora setup** — refreshes the local launcher/desktop integration.

If ATS is already running, the launcher leaves it running.

## Map updates

TruckNav Linux tracks the installed ATS Steam build and the build used for the current generated map.

When ATS updates, the web control center can show that a map update is available. **Rebuild ATS Map** regenerates the routing graph, visual PMTiles, sprites, cities, companies, and map metadata from the locally installed ATS files.

A map rebuild can take a while, so TruckNav asks for confirmation first.

## Stable and Testing

```text
Stable  -> master
Testing -> development worktree / feature branch
```

This lets new map or Linux changes be tested without disturbing the normal checkout. When a tested feature is merged into `master`, switch the launcher back to **Stable**.

## LAN / browser use

TruckNav is served as a web app, so the same instance can be opened from another computer, tablet, or phone on the network.

Normal TruckNav settings are shared by the host, so changing units, colors, DLC ownership, or navigation settings from one browser updates the shared configuration.

This personal fork currently allows shared administration for clients that can reach the TruckNav instance. If the service is ever exposed to an untrusted/public network, disable shared administration until authentication is added:

```bash
TRUCKNAV_SHARED_ADMIN=0
```

## Development

```bash
# UI only
bash scripts/linux/launch-web-only.sh

# TruckNav + telemetry
bash scripts/linux/launch-trucknav.sh

# ATS + TruckNav
bash scripts/linux/launch-ats-trucknav.sh
```

More detailed notes:

- [`docs/TRUCKNAV_LINUX.md`](docs/TRUCKNAV_LINUX.md)
- [`docs/ATS_MAP_BUILD.md`](docs/ATS_MAP_BUILD.md)

## Notes

TruckNav Linux is a personal Linux-focused fork and is not presented as the official upstream TruckNav release. American Truck Simulator, Euro Truck Simulator 2, and SCS Software are separate from this project.

This repository remains under the license included in [`LICENSE`](LICENSE).

---

**Original project:** [Rares-Muntean/TruckNav-Sim](https://github.com/Rares-Muntean/TruckNav-Sim)  
**Thanks & acknowledgements:** [THANKS.md](THANKS.md)
