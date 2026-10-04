#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_ROOT="${TRUCKNAV_MAP_TOOLS_ROOT:-$REPO_ROOT/.tools/map-data}"
MAPS_DIR="$TOOLS_ROOT/trucksim-maps"
NODE_VERSION="${TRUCKNAV_MAP_NODE_VERSION:-24.13.0}"
MAPS_REVISION="d56d0e3fb319230e84284f3029f8bda2c4b572a2"
PATCH_SCRIPT="$REPO_ROOT/scripts/map-data/patch-trucksim-maps-south-dakota.py"

case "$(uname -m)" in
    x86_64) NODE_ARCH="x64" ;;
    aarch64|arm64) NODE_ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 2
        ;;
esac

NODE_BASENAME="node-v${NODE_VERSION}-linux-${NODE_ARCH}"
NODE_HOME="$TOOLS_ROOT/$NODE_BASENAME"
NODE_ARCHIVE="$TOOLS_ROOT/$NODE_BASENAME.tar.xz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/$NODE_BASENAME.tar.xz"

mkdir -p "$TOOLS_ROOT"

missing_build_tools=()
for cmd in git python3 make gcc g++; do
    command -v "$cmd" >/dev/null 2>&1 || missing_build_tools+=("$cmd")
done
if ((${#missing_build_tools[@]})); then
    echo "Missing native build tools: ${missing_build_tools[*]}" >&2
    echo "On Fedora, install them with:" >&2
    echo "  sudo dnf install git python3 make gcc gcc-c++" >&2
    exit 4
fi

download() {
    local url="$1"
    local output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --retry-delay 2 "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output" "$url"
    else
        echo "Need curl or wget to download Node.js." >&2
        exit 3
    fi
}

if [[ ! -x "$NODE_HOME/bin/node" ]]; then
    echo "Downloading local Node.js $NODE_VERSION..."
    download "$NODE_URL" "$NODE_ARCHIVE"
    tar -xJf "$NODE_ARCHIVE" -C "$TOOLS_ROOT"
    rm -f "$NODE_ARCHIVE"
fi

export PATH="$NODE_HOME/bin:$PATH"

echo "Using node: $(node --version)"
echo "Using npm:  $(npm --version)"

if [[ ! -d "$MAPS_DIR/.git" ]]; then
    echo "Cloning truckermudgeon/maps..."
    git clone https://github.com/truckermudgeon/maps.git "$MAPS_DIR"
fi

echo "Checking out pinned map tooling revision..."
git -C "$MAPS_DIR" fetch origin main
git -C "$MAPS_DIR" checkout --detach "$MAPS_REVISION"
git -C "$MAPS_DIR" reset --hard "$MAPS_REVISION"

python3 "$PATCH_SCRIPT" "$MAPS_DIR"

echo
echo "Installing map-tool dependencies..."
(
    cd "$MAPS_DIR"
    HUSKY=0 npm install
)

echo
echo "Building native ATS/ETS2 parser addon..."
(
    cd "$MAPS_DIR"
    npm run build -w packages/clis/parser
)

cat > "$TOOLS_ROOT/env.sh" <<EOF
export TRUCKNAV_MAP_TOOLS_ROOT="$TOOLS_ROOT"
export TRUCKNAV_MAPS_DIR="$MAPS_DIR"
export PATH="$NODE_HOME/bin:\$PATH"
EOF

echo
echo "Map tooling ready."
echo "Tools dir: $MAPS_DIR"
echo "Pinned revision: $MAPS_REVISION"
