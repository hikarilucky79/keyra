#!/bin/bash
# Keyra Debian Packaging Script
set -e

# Base directories
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING_DIR="$WORKSPACE_DIR/packaging"
TEMP_DIR="$PACKAGING_DIR/deb_build_temp"

echo "=== Building Keyra for Debian ==="

# 1. Build Rust Daemon
echo "-> Building keyra-daemon in release mode..."
cd "$WORKSPACE_DIR/keyra-daemon"
cargo build --release

# 2. Build Flutter UI
echo "-> Building keyra-flutter in release mode..."
cd "$WORKSPACE_DIR/keyra-flutter"
flutter build linux --release

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
cp "$WORKSPACE_DIR/keyra-daemon/target/release/keyra-daemon" "$TEMP_DIR/usr/bin/keyra-daemon"
cp -r "$WORKSPACE_DIR/keyra-flutter/build/linux/x64/release/bundle/"* "$TEMP_DIR/opt/keyra/"
cp "$PACKAGING_DIR/keyra.desktop" "$TEMP_DIR/usr/share/applications/keyra.desktop"
cp "$PACKAGING_DIR/keyra.service" "$TEMP_DIR/usr/lib/systemd/user/keyra.service"
cp "$WORKSPACE_DIR/keyra-flutter/assets/icons/tray_icon.png" "$TEMP_DIR/usr/share/pixmaps/keyra.png"

# Create symlink for the UI
ln -sf "/opt/keyra/keyra_app" "$TEMP_DIR/usr/bin/keyra-ui"

# Create DEBIAN/control file
cat <<EOF > "$TEMP_DIR/DEBIAN/control"
Package: keyra
Version: 0.1.0
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
echo "-> Generating .deb package..."
dpkg-deb --build "$TEMP_DIR" "$PACKAGING_DIR/keyra_0.1.0_amd64.deb"

# Clean up
rm -rf "$TEMP_DIR"

echo "=== Build Complete! Package created at packaging/keyra_0.1.0_amd64.deb ==="
