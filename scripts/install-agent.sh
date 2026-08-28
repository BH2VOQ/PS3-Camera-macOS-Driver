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
DOMAIN="gui/$(id -u)"
SERVICE="$DOMAIN/$LABEL"

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
	<key>ThrottleInterval</key><integer>2</integer>
	<key>ProcessType</key><string>Background</string>
	<key>StandardOutPath</key><string>$LOG</string>
	<key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

chmod 644 "$PLIST"
plutil -lint "$PLIST" >/dev/null

# 干净卸载旧任务。不同 macOS 版本对 service target / plist path 的 bootout
# 行为略有差异，因此两种形式都尝试，并清掉可能残留的旧 feeder 进程。
launchctl disable "$SERVICE" 2>/dev/null || true
launchctl bootout "$SERVICE" 2>/dev/null || true
launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true
pkill -x ps3eye-feed 2>/dev/null || true
sleep 1

launchctl enable "$SERVICE" 2>/dev/null || true
if ! launchctl bootstrap "$DOMAIN" "$PLIST"; then
    echo "❌ LaunchAgent bootstrap 失败。当前诊断："
    echo "   plist: $PLIST"
    plutil -p "$PLIST" || true
    launchctl print "$SERVICE" 2>/dev/null || true
    echo ""
    echo "可手动执行以下命令获取更完整的 launchd 错误："
    echo "launchctl bootout '$DOMAIN' '$PLIST' 2>/dev/null || true"
    echo "launchctl bootstrap '$DOMAIN' '$PLIST'"
    exit 1
fi

launchctl kickstart -k "$SERVICE" 2>/dev/null || true

sleep 2
if pgrep -x ps3eye-feed >/dev/null; then
    echo "✅ LaunchAgent 已安装并常驻运行（开机自启）"
    echo "   日志：$LOG"
    echo "   停止：./scripts/uninstall-agent.sh"
else
    echo "⚠️  Agent 已安装但 feed 未运行，看日志：$LOG"
fi
