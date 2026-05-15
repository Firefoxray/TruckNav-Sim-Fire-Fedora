#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
STEAM_APP_ID="270880"

mkdir -p "$BIN_DIR" "$DESKTOP_DIR"

echo "Installing Fedora dependencies..."
sudo dnf install -y nodejs npm git protontricks kde-cli-tools konsole

echo "Installing npm dependencies..."
cd "$APP_DIR"
npm install

echo "Creating TruckNav telemetry launcher..."
cat > "$BIN_DIR/trucknav-telemetry" <<EOF
#!/usr/bin/env bash
protontricks-launch --appid $STEAM_APP_ID "\$HOME/Applications/TruckNav-Sim/electron/bin/TruckNavTelemetry.exe"
EOF
chmod +x "$BIN_DIR/trucknav-telemetry"

echo "Creating TruckNav all-in-one launcher..."
cat > "$BIN_DIR/trucknav-all" <<'EOF'
#!/usr/bin/env bash
cd "$HOME/Applications/TruckNav-Sim" || exit 1

npm run dev -- --host 0.0.0.0 &
WEB_PID=$!

protontricks-launch --appid 270880 "$HOME/Applications/TruckNav-Sim/electron/bin/TruckNavTelemetry.exe" &
TELEM_PID=$!

cleanup() {
  kill "$WEB_PID" "$TELEM_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait
EOF
chmod +x "$BIN_DIR/trucknav-all"

echo "Creating GUI launcher..."
cat > "$BIN_DIR/trucknav-all-gui" <<'EOF'
#!/usr/bin/env bash
konsole --noclose -e "$HOME/.local/bin/trucknav-all"
EOF
chmod +x "$BIN_DIR/trucknav-all-gui"

echo "Creating desktop entry..."
cat > "$DESKTOP_DIR/trucknav-sim.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=TruckNav Sim
Comment=Start TruckNav-Sim web app and ATS telemetry helper
Exec=$HOME/.local/bin/trucknav-all-gui
Icon=applications-games
Terminal=false
Categories=Game;Utility;
StartupNotify=true
EOF

chmod +x "$DESKTOP_DIR/trucknav-sim.desktop"
kbuildsycoca6 || true

echo "Done. Search for TruckNav Sim in your launcher."
