#!/bin/bash
# Build script for OpenCoolscan
# Run from project directory: ./build.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Avoid colon in path issues by building in /tmp
BUILD_DIR="/tmp/OpenCoolscanBuild_$$"

cleanup() {
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

echo "→ Copying sources to clean build path..."
mkdir -p "$BUILD_DIR"
rsync -a --exclude '.build' --exclude 'OpenCoolscan.app' --exclude '.git' \
  "$SCRIPT_DIR/" "$BUILD_DIR/"

echo "→ Building (release)..."
cd "$BUILD_DIR"
swift build --configuration release 2>&1

# SPM may place the binary under .build/release or .build/<triple>/release
BIN=""
for candidate in \
  "$BUILD_DIR/.build/release/OpenCoolscan" \
  "$BUILD_DIR/.build/out/Products/Release/OpenCoolscan" \
  $(find "$BUILD_DIR/.build" -type f -name OpenCoolscan -path '*/release/*' 2>/dev/null | head -1)
do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    BIN="$candidate"
    break
  fi
done

if [[ -z "$BIN" ]]; then
  echo "✗ Could not find built OpenCoolscan binary under .build/"
  find "$BUILD_DIR/.build" -name 'OpenCoolscan' -type f 2>/dev/null || true
  exit 1
fi

echo "→ Packaging app bundle (from $BIN)..."
APP_OUT="$SCRIPT_DIR/OpenCoolscan.app"
rm -rf "$APP_OUT"
mkdir -p "$APP_OUT/Contents/MacOS" "$APP_OUT/Contents/Resources"
cp "$BIN" "$APP_OUT/Contents/MacOS/"
chmod +x "$APP_OUT/Contents/MacOS/OpenCoolscan"
cp "$SCRIPT_DIR/Sources/OpenCoolscan/Resources/Info.plist" "$APP_OUT/Contents/"

# Copy SPM resource bundle if present
if [[ -d "$BUILD_DIR/.build/release/OpenCoolscan_OpenCoolscan.bundle" ]]; then
  cp -R "$BUILD_DIR/.build/release/OpenCoolscan_OpenCoolscan.bundle" "$APP_OUT/Contents/Resources/"
fi

echo "✓ Built: $APP_OUT"
echo "  Run with: open \"$APP_OUT\""
echo "  Requires: brew install sane-backends  (and coolscan3 for Nikon film scanners)"
