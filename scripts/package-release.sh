#!/bin/bash
# package-release.sh — create distributable DMG and ZIP packages
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0.0"
APP_NAME="PS3-Camera-macOS-Driver"
APP="dist/${APP_NAME}.app"
RELEASE_DIR="dist/release"
DMG="${RELEASE_DIR}/${APP_NAME}-v${VERSION}.dmg"
ZIP="${RELEASE_DIR}/${APP_NAME}-v${VERSION}.zip"
STAGING="dist/dmg-staging"

if [ ! -d "$APP" ]; then
  echo "App bundle not found: $APP"
  echo "Run ./scripts/build-app.sh first."
  exit 1
fi

rm -rf "$RELEASE_DIR" "$STAGING"
mkdir -p "$RELEASE_DIR" "$STAGING"

# Verify the application bundle before packaging.
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# ZIP preserves the .app bundle and metadata for direct distribution.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# DMG contains the app and a convenient Applications symlink.
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create \
  -volname "PS3 Camera macOS Driver" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGING"

shasum -a 256 "$DMG" "$ZIP" > "$RELEASE_DIR/SHA256SUMS.txt"

echo "✅ Release packages created:"
echo "   $DMG"
echo "   $ZIP"
echo "   $RELEASE_DIR/SHA256SUMS.txt"
