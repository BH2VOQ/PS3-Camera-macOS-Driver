#!/bin/bash
# install-agent.sh — 安装 LaunchAgent 常驻后台（开机自启、崩溃自动拉起）
# 用法：./scripts/install-agent.sh   （从源码/CLI 包安装）
set -e
cd "$(dirname "$0")/.."

SUPPORT="$HOME/Library/Application Support/PS3Eye-VirtualCam"
AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENT_DIR/com.bh2voq.ps3eye-vcam.plist"
LOG="$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
LABEL="com.bh2voq.ps3eye-vcam"

mkdir -p "$SUPPORT" "$AGENT_DIR" "$(dirname "$LOG")"
cp -f bin/ps3eye-feed "$SUPPORT/ps3eye-feed"
chmod +x "$SUPPORT/ps3eye-feed"

cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key>
	<array><string>$SUPPORT/ps3eye-feed</string></array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>ThrottleInterval</key><integer>10</integer>
	<key>ProcessType</key><string>Background</string>
	<key>StandardOutPath</key><string>$LOG</string>
	<key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

# 先卸载旧的再装新的（幂等）
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true

sleep 2
if pgrep -x ps3eye-feed >/dev/null; then
    echo "✅ LaunchAgent 已安装并常驻运行（开机自启）"
    echo "   日志：$LOG"
    echo "   停止：./scripts/uninstall-agent.sh"
else
    echo "⚠️  Agent 已安装但 feed 未运行，看日志：$LOG"
fi
