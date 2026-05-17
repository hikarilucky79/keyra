#!/bin/bash
# Keyra Master Packaging Script
# Compiles and generates all distribution formats (.deb and AppImage) in one command.
set -e

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=========================================================="
echo "       KEYRA MASTER PACKAGING PIPELINE"
echo "=========================================================="

# Make sure sub-scripts are executable
chmod +x "$WORKSPACE_DIR/packaging/build_deb.sh"
chmod +x "$WORKSPACE_DIR/packaging/build_appimage.sh"

# 1. Build Debian Package
echo ""
echo "[Step 1/2] Generating Debian Package..."
"$WORKSPACE_DIR/packaging/build_deb.sh"

# 2. Build AppImage Package
echo ""
echo "[Step 2/2] Generating Portable AppImage..."
"$WORKSPACE_DIR/packaging/build_appimage.sh"

echo ""
echo "=========================================================="
echo "       ALL PACKAGES BUILT SUCCESSFULLY!"
echo "=========================================================="
echo "Generated files in packaging/:"
ls -la "$WORKSPACE_DIR/packaging" | grep -E '(\.deb|\.AppImage)$'
echo "=========================================================="
