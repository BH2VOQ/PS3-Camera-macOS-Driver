#!/bin/bash
# uninstall-agent.sh — 卸载 LaunchAgent 常驻（停止驱动 + 移除自启）
set -e
cd "$(dirname "$0")/.."

LABEL="com.bh2voq.ps3eye-vcam"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SUPPORT="$HOME/Library/Application Support/PS3Eye-VirtualCam"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x ps3eye-feed 2>/dev/null || true
rm -f "$PLIST"
# 保留驱动文件（重装更快），如需彻底删除加 --purge
if [ "$1" = "--purge" ]; then
    rm -rf "$SUPPORT"
fi

sleep 1
if pgrep -x ps3eye-feed >/dev/null; then
    echo "⚠️  feed 仍在运行（U 态等内核清理）"
else
    echo "✅ 已停止并移除开机自启"
fi
