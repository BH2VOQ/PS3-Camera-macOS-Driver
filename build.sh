#!/bin/bash
# build.sh — 构建 PS3Eye-VirtualCam（Apple Silicon / arm64 原生）
# 产物：bin/ps3eye-feed（常驻 640x480@30 feeder，带卡帧 watchdog）
set -e
cd "$(dirname "$0")"

echo "🔧 构建 PS3Eye-VirtualCam (arm64)..."

# ps3eye-feed — 抓帧喂 OBS Virtual Camera（静态链接 libusb）
clang++ -std=gnu++14 -stdlib=libc++ -fobjc-arc -fobjc-weak -O2 -arch arm64 \
  -I src -I src/ps3eye -I lib/libusb \
  src/ps3eye-feed.mm src/ps3eye/ps3eye.cpp \
  lib/libusb/libusb-1.0.a \
  -framework Foundation -framework AVFoundation \
  -framework CoreMedia -framework CoreMediaIO -framework CoreVideo -framework IOSurface \
  -framework IOKit -framework CoreFoundation -framework Security -lobjc \
  -o bin/ps3eye-feed
echo "  ✅ bin/ps3eye-feed"

echo ""
echo "✅ 构建完成。启动：./scripts/start.sh"
