#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_PATH="$REPO_ROOT/assets/icon-only.png"
mkdir -p "$BIN_DIR" "$DESKTOP_DIR"

if [[ ! -f "$ICON_PATH" ]]; then
  echo "Warning: expected TruckNav icon not found at $ICON_PATH" >&2
fi

cat > "$BIN_DIR/trucknav-linux-launcher" <<EOF_WRAPPER
#!/usr/bin/env bash
export TRUCKNAV_REPO_ROOT="$REPO_ROOT"
exec python3 "$REPO_ROOT/scripts/linux/trucknav-linux-launcher.py" "\$@"
EOF_WRAPPER
chmod +x "$BIN_DIR/trucknav-linux-launcher"

cat > "$BIN_DIR/trucknav-all" <<EOF_WRAPPER
#!/usr/bin/env bash
export TRUCKNAV_REPO_ROOT="$REPO_ROOT"
exec "$REPO_ROOT/scripts/linux/launch-trucknav.sh" --wait "\$@"
EOF_WRAPPER
chmod +x "$BIN_DIR/trucknav-all"

cat > "$BIN_DIR/trucknav-ats-all" <<EOF_WRAPPER
#!/usr/bin/env bash
export TRUCKNAV_REPO_ROOT="$REPO_ROOT"
exec "$REPO_ROOT/scripts/linux/launch-ats-trucknav.sh" "\$@"
EOF_WRAPPER
chmod +x "$BIN_DIR/trucknav-ats-all"

cat > "$BIN_DIR/trucknav-stop" <<EOF_WRAPPER
#!/usr/bin/env bash
export TRUCKNAV_REPO_ROOT="$REPO_ROOT"
exec "$REPO_ROOT/scripts/linux/stop-trucknav.sh" "\$@"
EOF_WRAPPER
chmod +x "$BIN_DIR/trucknav-stop"

cat > "$DESKTOP_DIR/trucknav-linux-launcher.desktop" <<EOF_DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=TruckNav Linux Launcher
Comment=Manage TruckNav-Sim and American Truck Simulator on Linux
Exec=$BIN_DIR/trucknav-linux-launcher
Icon=$ICON_PATH
Terminal=false
Categories=Game;Utility;
StartupNotify=true
StartupWMClass=TruckNavLinuxLauncher
EOF_DESKTOP
chmod +x "$DESKTOP_DIR/trucknav-linux-launcher.desktop"

cat > "$DESKTOP_DIR/trucknav-sim.desktop" <<EOF_DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=TruckNav Sim
Comment=Start TruckNav-Sim web app and ATS telemetry helper
Exec=$BIN_DIR/trucknav-all
Icon=$ICON_PATH
Terminal=true
Categories=Game;Utility;
StartupNotify=true
EOF_DESKTOP
chmod +x "$DESKTOP_DIR/trucknav-sim.desktop"

if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 >/dev/null 2>&1 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
  kbuildsycoca5 >/dev/null 2>&1 || true
fi

echo "Installed desktop entries:"
echo "- $DESKTOP_DIR/trucknav-linux-launcher.desktop"
echo "- $DESKTOP_DIR/trucknav-sim.desktop"
echo "Installed command wrappers in $BIN_DIR."
