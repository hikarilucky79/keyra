#!/bin/bash
# Keyra AppImage Packaging Script
set -e

# Base directories
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING_DIR="$WORKSPACE_DIR/packaging"
APPDIR="$PACKAGING_DIR/AppDir"

echo "=== Building Keyra AppImage ==="

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

# 3. Create AppDir Structure
echo "-> Structuring AppDir..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/share/metainfo"

# 4. Copy Binaries and Assets
echo "-> Copying binaries and configuration assets..."
cp "$DAEMON_BIN" "$APPDIR/usr/bin/keyra-daemon"
cp -r "$FLUTTER_BUNDLE/"* "$APPDIR/usr/bin/"
mv "$APPDIR/usr/bin/keyra_app" "$APPDIR/usr/bin/keyra"

# Copy icon — try multiple locations
if [ -f "$WORKSPACE_DIR/keyra-flutter/assets/icons/tray_icon.png" ]; then
    cp "$WORKSPACE_DIR/keyra-flutter/assets/icons/tray_icon.png" "$APPDIR/io.github.hikarilucky79.keyra.png"
elif [ -f "$WORKSPACE_DIR/app_logo.png" ]; then
    cp "$WORKSPACE_DIR/app_logo.png" "$APPDIR/io.github.hikarilucky79.keyra.png"
else
    echo "Warning: No icon file found, using placeholder."
    printf '\x89PNG\r\n\x1a\n' > "$APPDIR/io.github.hikarilucky79.keyra.png"
fi

# Write desktop entry file into AppDir root (required by AppImage)
cat <<EOF > "$APPDIR/io.github.hikarilucky79.keyra.desktop"
[Desktop Entry]
Name=Keyra
Comment=Premium Keyboard Audio Feedback Configuration
Exec=keyra_app %U
Icon=io.github.hikarilucky79.keyra
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

# Ensure dynamic linker finds the bundled shared libraries
export LD_LIBRARY_PATH="$HERE/usr/bin/lib:$LD_LIBRARY_PATH"

# Start the daemon in the background if not already running
if ! pgrep -x "keyra-daemon" > /dev/null; then
    "$HERE/usr/bin/keyra-daemon" &
fi

# Change working directory to the binary location so relative assets (data/ and lib/) resolve correctly
cd "$HERE/usr/bin"
exec ./keyra "$@"
EOF
chmod +x "$APPDIR/AppRun"

# 6. Download and run appimagetool
echo "-> Acquiring appimagetool..."
cd "$PACKAGING_DIR"

if [ ! -f appimagetool ] || [ ! -s appimagetool ]; then
    echo "-> Downloading appimagetool..."
    rm -f appimagetool
    if command -v wget >/dev/null 2>&1; then
        wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O appimagetool
    elif command -v curl >/dev/null 2>&1; then
        curl -sL https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -o appimagetool
    else
        echo "Error: Neither wget nor curl is installed."
        exit 1
    fi
fi

chmod +x appimagetool

echo "-> Generating Keyra-x86_64.AppImage..."
export ARCH=x86_64
export APPIMAGE_EXTRACT_AND_RUN=1
./appimagetool "$APPDIR" "$PACKAGING_DIR/Keyra-x86_64.AppImage"

# Clean up
rm -rf "$APPDIR"

echo "=== Build Complete! Portable AppImage created at packaging/Keyra-x86_64.AppImage ==="
