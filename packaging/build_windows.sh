#!/bin/bash
# Keyra Windows Build Script (cross-compile via MinGW-w64 on Arch Linux)
# Requires: sudo pacman -S mingw-w64-gcc
#            rustup target add x86_64-pc-windows-gnu
set -e
set -u

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$WORKSPACE_DIR/target/x86_64-pc-windows-gnu/release"
DIST_DIR="$WORKSPACE_DIR/packaging/releases/windows"

echo "=========================================================="
echo "       KEYRA WINDOWS BUILD PIPELINE"
echo "=========================================================="

# ── 1. Validate toolchain ──────────────────────────────────
MINGW_CC="${MINGW_PREFIX:-x86_64-w64-mingw32}-gcc"
if ! command -v "$MINGW_CC" &>/dev/null; then
  echo "Error: MinGW-w64 cross-compiler not found at '$MINGW_CC'."
  echo "Install it with:  sudo pacman -S mingw-w64-gcc"
  exit 1
fi

if ! rustup target list | grep -q "x86_64-pc-windows-gnu (installed)"; then
  echo "-> Installing Rust Windows target..."
  rustup target add x86_64-pc-windows-gnu
fi

echo "CC         : $MINGW_CC"
echo "Windows Tgt: x86_64-pc-windows-gnu"

# ── 2. Build Rust daemon ───────────────────────────────────
echo ""
echo "-> [1/2] Building keyra-daemon for Windows (release)..."
cd "$WORKSPACE_DIR/keyra-daemon"
# Some crates ship prebuilt winapi deps — force recompile for cross-target
CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS="-C prefer-dynamic" \
cargo build --release --target x86_64-pc-windows-gnu

DAEMON_EXE="$TARGET_DIR/keyra-daemon.exe"
if [ ! -f "$DAEMON_EXE" ]; then
  echo "Error: $DAEMON_EXE not found after build."
  exit 1
fi
echo "  ✓ keyra-daemon.exe  ($(du -sh "$DAEMON_EXE" | cut -f1))"

# ── 3. Build Flutter UI (Windows release) ──────────────────
echo ""
echo "-> [2/2] Building keyra-flutter for Windows (release)..."
cd "$WORKSPACE_DIR/keyra-flutter"

# First build Linux (already works), then release for Windows
# Flutter needs to generate the Windows runner if it does not exist yet
if [ ! -d "windows/runner" ]; then
  echo "-> Creating Flutter Windows project..."
  flutter config --enable-windows-desktop >/dev/null 2>&1
  flutter create --platforms=windows . 2>/dev/null || true
fi

flutter build windows --release

FLUTTER_EXE="$WORKSPACE_DIR/keyra-flutter/build/windows/x64/runner/Release/keyra_app.exe"
if [ ! -f "$FLUTTER_EXE" ]; then
  echo "Error: $FLUTTER_EXE not found after build."
  exit 1
fi
echo "  ✓ keyra_app.exe  ($(du -sh "$FLUTTER_EXE" | cut -f1))"

# ── 4. Assemble distribution ───────────────────────────────
echo ""
echo "-> Assembling Keyra-Windows-x64.zip..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Build portable stub that starts daemon + UI side by side
STUB_DIR="$WORKSPACE_DIR/packaging/windows_stub"
mkdir -p "$STUB_DIR"
cp "$DAEMON_EXE"        "$STUB_DIR/keyra-daemon.exe"
cp "$FLUTTER_EXE"       "$STUB_DIR/keyra_app.exe"

DIST_ZIP="$WORKSPACE_DIR/packaging/Keyra-Windows-x64.zip"
cd "$STUB_DIR"
zip -rq "$DIST_ZIP" .

echo "  ✓ $(ls -lh "$DIST_ZIP" | awk '{print $5}')"
rm -rf "$STUB_DIR"

echo ""
echo "=========================================================="
echo "       WINDOWS BUILD COMPLETE"
echo "=========================================================="
echo "Output: $DIST_ZIP"
echo "=========================================================="
