#!/bin/bash
# build-app.sh — build the PS3 Camera macOS Driver menu bar app
# Output: dist/PS3-Camera-macOS-Driver.app
set -e
cd "$(dirname "$0")/.."

APP="dist/PS3-Camera-macOS-Driver.app"
EXECUTABLE="PS3-Camera-macOS-Driver"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "🔧 Building menu bar app..."
clang -fobjc-arc -O2 -framework Cocoa -o "$APP/Contents/MacOS/$EXECUTABLE" src/app/PS3EyeVCMenu.m

echo "📦 Bundling feeder..."
cp bin/ps3eye-feed "$APP/Contents/Resources/ps3eye-feed"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$EXECUTABLE</string>
	<key>CFBundleIdentifier</key>
	<string>com.bh2voq.ps3eye-vcam</string>
	<key>CFBundleName</key>
	<string>PS3 Camera macOS Driver</string>
	<key>CFBundleDisplayName</key>
	<string>PS3 Camera macOS Driver</string>
	<key>CFBundleVersion</key>
	<string>0.1.2</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.2-beta</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSAppleEventsUsageDescription</key>
	<string>Controls the PS3 Eye camera bridge and background feeder.</string>
</dict>
</plist>
PLIST

echo "✍️  Applying ad-hoc signature..."
codesign --force --deep -s - "$APP" 2>/dev/null || true

echo ""
echo "✅ Build complete: $APP"
echo "   Copy it to /Applications and launch it to control the camera from the menu bar."
echo "   If Gatekeeper blocks the unsigned app on first launch, right-click it and choose Open."
