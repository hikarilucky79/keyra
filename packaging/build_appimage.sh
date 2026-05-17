#!/bin/bash
# Keyra AppImage Packaging Script
set -e

# Base directories
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING_DIR="$WORKSPACE_DIR/packaging"
APPDIR="$PACKAGING_DIR/AppDir"

echo "=== Building Keyra AppImage ==="

# 1. Build Rust Daemon
echo "-> Building keyra-daemon in release mode..."
cd "$WORKSPACE_DIR/keyra-daemon"
cargo build --release

# 2. Build Flutter UI
echo "-> Building keyra-flutter in release mode..."
cd "$WORKSPACE_DIR/keyra-flutter"
flutter build linux --release

# 3. Create AppDir Structure
echo "-> Structuring AppDir..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/share/metainfo"

# 4. Copy Binaries and Assets
echo "-> Copying binaries and configuration assets..."
cp "$WORKSPACE_DIR/keyra-daemon/target/release/keyra-daemon" "$APPDIR/usr/bin/keyra-daemon"
cp -r "$WORKSPACE_DIR/keyra-flutter/build/linux/x64/release/bundle/"* "$APPDIR/usr/bin/"
cp "$WORKSPACE_DIR/keyra-flutter/assets/icons/tray_icon.png" "$APPDIR/keyra.png"

# Write desktop entry file into AppDir root (required by AppImage)
cat <<EOF > "$APPDIR/keyra.desktop"
[Desktop Entry]
Name=Keyra
Comment=Premium Keyboard Audio Feedback Configuration
Exec=keyra_app %U
Icon=keyra
Terminal=false
Type=Application
Categories=Utility;Settings;Audio;
Keywords=keyboard;audio;sound;typing;
StartupNotify=true
EOF

# 5. Create AppRun script in AppDir root
echo "-> Creating AppRun launcher script..."
cat <<'EOF' > "$APPDIR/AppRun"
#!/bin/sh
HERE="$(dirname "$(readlink -f "${0}")")"

# Start the daemon in the background if not already running
if ! pgrep -x "keyra-daemon" > /dev/null; then
    "$HERE/usr/bin/keyra-daemon" &
fi

# Run the Flutter UI
exec "$HERE/usr/bin/keyra_app" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# 6. Download and run appimagetool
echo "-> Acquiring appimagetool..."
cd "$PACKAGING_DIR"

if [ ! -f appimagetool ]; then
    echo "-> Downloading appimagetool..."
    # Download 64-bit AppImage tool
    if command -v wget >/dev/null 2>&1; then
        wget -q https://github.com/AppImage/AppImageKit/releases/download/13/appimagetool-x86_64.AppImage -O appimagetool
    elif command -v curl >/dev/null 2>&1; then
        curl -sL https://github.com/AppImage/AppImageKit/releases/download/13/appimagetool-x86_64.AppImage -o appimagetool
    else
        echo "Error: Neither wget nor curl is installed. Please install one of them to download appimagetool automatically."
        exit 1
    fi
    chmod +x appimagetool
fi

echo "-> Generating Keyra-x86_64.AppImage..."
export ARCH=x86_64
./appimagetool "$APPDIR" "$PACKAGING_DIR/Keyra-x86_64.AppImage"

# Clean up
rm -rf "$APPDIR"

echo "=== Build Complete! Portable AppImage created at packaging/Keyra-x86_64.AppImage ==="
