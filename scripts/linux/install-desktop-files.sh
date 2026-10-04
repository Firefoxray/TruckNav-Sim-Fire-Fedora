#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/trucknav-linux-launcher"
CONFIG_PATH="$CONFIG_DIR/config.json"
ICON_PATH="$REPO_ROOT/assets/icon-only.png"
mkdir -p "$BIN_DIR" "$DESKTOP_DIR" "$CONFIG_DIR"

if [[ ! -f "$ICON_PATH" ]]; then
  echo "Warning: expected TruckNav icon not found at $ICON_PATH" >&2
fi

requested_channel=""
if [[ "${1:-}" == "--activate" ]]; then
  requested_channel="${2:-}"
  if [[ "$requested_channel" != "stable" && "$requested_channel" != "testing" ]]; then
    echo "Usage: $0 [--activate stable|testing]" >&2
    exit 2
  fi
fi

current_branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
stable_repo=""
testing_repo=""

while IFS= read -r line; do
  case "$line" in
    worktree\ *)
      wt_path="${line#worktree }"
      ;;
    branch\ refs/heads/master)
      stable_repo="$wt_path"
      ;;
    branch\ refs/heads/*)
      wt_branch="${line#branch refs/heads/}"
      if [[ "$wt_branch" != "master" ]]; then
        if [[ "$wt_path" == "$REPO_ROOT" || -z "$testing_repo" ]]; then
          testing_repo="$wt_path"
        fi
      fi
      ;;
  esac
done < <(git -C "$REPO_ROOT" worktree list --porcelain)

if [[ "$current_branch" == "master" ]]; then
  stable_repo="$REPO_ROOT"
else
  testing_repo="$REPO_ROOT"
fi

if [[ -z "$stable_repo" ]]; then
  sibling="$(dirname "$REPO_ROOT")/TruckNav-Sim-Fire-Fedora"
  [[ -f "$sibling/package.json" ]] && stable_repo="$sibling"
fi

if [[ -z "$testing_repo" ]]; then
  sibling="$(dirname "$REPO_ROOT")/TruckNav-Sim-South-Dakota"
  [[ -f "$sibling/package.json" ]] && testing_repo="$sibling"
fi

if [[ -z "$requested_channel" ]]; then
  if [[ "$current_branch" == "master" ]]; then
    requested_channel="stable"
  else
    requested_channel="testing"
  fi
fi

python3 - "$CONFIG_PATH" "$requested_channel" "$stable_repo" "$testing_repo" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
active = sys.argv[2]
stable = sys.argv[3]
testing = sys.argv[4]

try:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        config = {}
except (OSError, json.JSONDecodeError):
    config = {}

channels = config.get("channels")
if not isinstance(channels, dict):
    channels = {}

if stable:
    channels["stable"] = stable
if testing:
    channels["testing"] = testing

if active not in channels:
    raise SystemExit(
        f"Cannot activate {active!r}: no repository path is registered for that channel"
    )

config["channels"] = channels
config["active_channel"] = active
config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY

cat > "$BIN_DIR/trucknav-active-repo" <<'EOF_HELPER'
#!/usr/bin/env bash
set -euo pipefail
CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/trucknav-linux-launcher/config.json"
python3 - "$CONFIG_PATH" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    config = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    raise SystemExit(f"TruckNav Linux channel config is unavailable: {exc}")

active = config.get("active_channel", "stable")
channels = config.get("channels") or {}
repo = channels.get(active)
if not repo:
    raise SystemExit(f"No TruckNav repository is configured for channel {active!r}")

repo_path = Path(repo).expanduser()
if not (repo_path / "package.json").is_file():
    raise SystemExit(f"Configured TruckNav repository does not exist: {repo_path}")

print(repo_path)
PY
EOF_HELPER
chmod +x "$BIN_DIR/trucknav-active-repo"

cat > "$BIN_DIR/trucknav-linux-launcher" <<EOF_WRAPPER
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$("$BIN_DIR/trucknav-active-repo")"
export TRUCKNAV_REPO_ROOT="$REPO_ROOT"
exec python3 "$REPO_ROOT/scripts/linux/trucknav-linux-launcher.py" "$@"
EOF_WRAPPER
chmod +x "$BIN_DIR/trucknav-linux-launcher"

cat > "$BIN_DIR/trucknav-all" <<EOF_WRAPPER
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$("$BIN_DIR/trucknav-active-repo")"
export TRUCKNAV_REPO_ROOT="$REPO_ROOT"
exec "$REPO_ROOT/scripts/linux/launch-trucknav.sh" --wait "$@"
EOF_WRAPPER
chmod +x "$BIN_DIR/trucknav-all"

cat > "$BIN_DIR/trucknav-ats-all" <<EOF_WRAPPER
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$("$BIN_DIR/trucknav-active-repo")"
export TRUCKNAV_REPO_ROOT="$REPO_ROOT"
exec "$REPO_ROOT/scripts/linux/launch-ats-trucknav.sh" "$@"
EOF_WRAPPER
chmod +x "$BIN_DIR/trucknav-ats-all"

cat > "$BIN_DIR/trucknav-stop" <<EOF_WRAPPER
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$("$BIN_DIR/trucknav-active-repo")"
export TRUCKNAV_REPO_ROOT="$REPO_ROOT"
exec "$REPO_ROOT/scripts/linux/stop-trucknav.sh" "$@"
EOF_WRAPPER
chmod +x "$BIN_DIR/trucknav-stop"

cat > "$DESKTOP_DIR/trucknav-linux-launcher.desktop" <<EOF_DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=TruckNav Linux Launcher
Comment=Manage TruckNav Linux and American Truck Simulator
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
Name=TruckNav Linux
Comment=Start the active TruckNav Linux channel and telemetry helper
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

echo "Installed TruckNav Linux channel-aware desktop entries."
echo "Active channel: $requested_channel"
[[ -n "$stable_repo" ]] && echo "Stable:  $stable_repo"
[[ -n "$testing_repo" ]] && echo "Testing: $testing_repo"
echo
echo "Launcher: $DESKTOP_DIR/trucknav-linux-launcher.desktop"
echo "Direct:   $DESKTOP_DIR/trucknav-sim.desktop"
echo "Config:   $CONFIG_PATH"
