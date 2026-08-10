#!/bin/bash
# build-app.sh — 构建菜单栏控制 App（PS3Eye-VirtualCam.app）
# 产物：dist/PS3Eye-VirtualCam.app（可拷贝到 /Applications，双击即用）
set -e
cd "$(dirname "$0")/.."

APP=dist/PS3Eye-VirtualCam.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "🔧 编译菜单栏 App..."
clang -fobjc-arc -O2 -framework Cocoa -o "$APP/Contents/MacOS/PS3Eye-VirtualCam" src/app/PS3EyeVCMenu.m

echo "📦 打包驱动二进制..."
cp bin/ps3eye-feed "$APP/Contents/Resources/ps3eye-feed"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>PS3Eye-VirtualCam</string>
	<key>CFBundleIdentifier</key>
	<string>com.bh2voq.ps3eye-vcam</string>
	<key>CFBundleName</key>
	<string>PS3Eye-VirtualCam</string>
	<key>CFBundleDisplayName</key>
	<string>PS3 Eye 虚拟摄像头</string>
	<key>CFBundleVersion</key>
	<string>0.1.1</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.1-beta</string>
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
	<string>用于控制 PS3 Eye 虚拟摄像头驱动。</string>
</dict>
</plist>
PLIST

echo "✍️  临时签名（ad-hoc）..."
codesign --force --deep -s - "$APP" 2>/dev/null || true

echo ""
echo "✅ 构建完成：$APP"
echo "   使用：拷贝到 /Applications，双击启动（菜单栏 🎥 图标控制）"
echo "   ⚠️ 未签名 App：首次双击如被 Gatekeeper 拦截，右键 → 打开 即可"
