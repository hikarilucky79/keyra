#!/bin/bash
# Keyra Debian Packaging Script
set -e

# Base directories
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING_DIR="$WORKSPACE_DIR/packaging"
TEMP_DIR="$PACKAGING_DIR/deb_build_temp"

echo "=== Building Keyra for Debian ==="

# 1. Resolve Rust Daemon Binary
# Check root target directory first, fallback to daemon-specific target
if [ -f "$WORKSPACE_DIR/target/release/keyra-daemon" ]; then
    DAEMON_BIN="$WORKSPACE_DIR/target/release/keyra-daemon"
elif [ -f "$WORKSPACE_DIR/keyra-daemon/target/release/keyra-daemon" ]; then
    DAEMON_BIN="$WORKSPACE_DIR/keyra-daemon/target/release/keyra-daemon"
else
    echo "-> Building keyra-daemon in release mode..."
    cd "$WORKSPACE_DIR/keyra-daemon"
    cargo build --release
    if [ -f "$WORKSPACE_DIR/target/release/keyra-daemon" ]; then
        DAEMON_BIN="$WORKSPACE_DIR/target/release/keyra-daemon"
    else
        DAEMON_BIN="$WORKSPACE_DIR/keyra-daemon/target/release/keyra-daemon"
    fi
fi

echo "-> Using daemon binary from: $DAEMON_BIN"

# 2. Build Flutter UI (skip if bundle already exists — CI pre-builds it)
FLUTTER_BUNDLE="$WORKSPACE_DIR/keyra-flutter/build/linux/x64/release/bundle"
if [ ! -d "$FLUTTER_BUNDLE" ]; then
    echo "-> Building keyra-flutter in release mode..."
    cd "$WORKSPACE_DIR/keyra-flutter"
    flutter build linux --release
else
    echo "-> Flutter Linux bundle already present, skipping build."
fi

# 3. Create Debian Package Structure
echo "-> Constructing debian package layout..."
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/DEBIAN"
mkdir -p "$TEMP_DIR/usr/bin"
mkdir -p "$TEMP_DIR/opt/keyra"
mkdir -p "$TEMP_DIR/usr/share/applications"
mkdir -p "$TEMP_DIR/usr/share/pixmaps"
mkdir -p "$TEMP_DIR/usr/lib/systemd/user"

# 4. Copy Binaries and Assets
echo "-> Copying binaries and configuration assets..."
cp "$DAEMON_BIN" "$TEMP_DIR/usr/bin/keyra-daemon"
cp -r "$FLUTTER_BUNDLE/"* "$TEMP_DIR/opt/keyra/"
cp "$PACKAGING_DIR/keyra.desktop" "$TEMP_DIR/usr/share/applications/keyra.desktop"
cp "$PACKAGING_DIR/keyra.service" "$TEMP_DIR/usr/lib/systemd/user/keyra.service"

# Copy icon — try multiple locations (prioritizing high-resolution main logo)
if [ -f "$WORKSPACE_DIR/app_logo.png" ]; then
    cp "$WORKSPACE_DIR/app_logo.png" "$TEMP_DIR/usr/share/pixmaps/keyra.png"
elif [ -f "$WORKSPACE_DIR/keyra-flutter/assets/icons/app_icon.png" ]; then
    cp "$WORKSPACE_DIR/keyra-flutter/assets/icons/app_icon.png" "$TEMP_DIR/usr/share/pixmaps/keyra.png"
elif [ -f "$WORKSPACE_DIR/keyra-flutter/assets/icons/tray_icon.png" ]; then
    cp "$WORKSPACE_DIR/keyra-flutter/assets/icons/tray_icon.png" "$TEMP_DIR/usr/share/pixmaps/keyra.png"
fi

# Create symlink for the UI
ln -sf "/opt/keyra/keyra_app" "$TEMP_DIR/usr/bin/keyra-ui"

# Get version from environment tag (GITHUB_REF_NAME) or fallback to v0.1.0
RAW_VERSION="${GITHUB_REF_NAME:-v0.1.0}"
# Remove 'v' prefix if present
VERSION="${RAW_VERSION#v}"

# Create DEBIAN/control file
cat <<EOF > "$TEMP_DIR/DEBIAN/control"
Package: keyra
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Depends: libc6, libgtk-3-0, libasound2
Maintainer: Hikari <hikari@projetos.com>
Description: Premium low-latency typing sound engine and UI
 Keyra is a low-latency typing sound engine for Linux.
 It features a beautiful macOS-inspired interface, custom sound packs,
 and automatic application profiling.
EOF

# 5. Build Debian Package
if ! command -v dpkg-deb &> /dev/null; then
    echo -e "\n⚠️  Aviso: 'dpkg-deb' não foi encontrado no seu sistema."
    echo "O empacotamento Debian (.deb) foi ignorado localmente."
    echo "Limpando arquivos temporários..."
    rm -rf "$TEMP_DIR"
else
    echo "-> Generating .deb package..."
    dpkg-deb --build "$TEMP_DIR" "$PACKAGING_DIR/keyra_${VERSION}_amd64.deb"
    rm -rf "$TEMP_DIR"
    echo "=== Build Complete! Package created at packaging/keyra_${VERSION}_amd64.deb ==="
fi
