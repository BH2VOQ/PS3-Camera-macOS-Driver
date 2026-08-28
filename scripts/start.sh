#!/bin/bash
# start.sh — 启动 PS3 Eye 虚拟摄像头（ps3eye-feed 单进程）
# 行为：摄像头与 OBS sink 保持稳定常驻，避免周期性 StopStream/StartStream 导致客户端掉线；
#       640x480@30，默认启用 AEC/AGC/AWB；USB 卡帧由 watchdog 触发服务自动恢复。
# 前置：OBS 已安装且虚拟摄像头扩展已激活（装 OBS 后 Start Virtual Camera 一次）
set -e
cd "$(dirname "$0")/.."

LABEL="com.bh2voq.ps3eye-vcam"
SUPPORT="$HOME/Library/Application Support/PS3Eye-VirtualCam"

# 若已安装 LaunchAgent 常驻，从源码目录启动时顺便刷新已安装 feeder，避免一直运行旧二进制。
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
    if [ -x ./bin/ps3eye-feed ]; then
        mkdir -p "$SUPPORT"
        cp -f ./bin/ps3eye-feed "$SUPPORT/ps3eye-feed"
        chmod +x "$SUPPORT/ps3eye-feed"
        launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
        echo "✅ 已刷新并重启 LaunchAgent 中的 ps3eye-feed。"
    else
        echo "ℹ️  已通过 LaunchAgent 常驻运行；当前目录没有 bin/ps3eye-feed，未执行升级。"
    fi
    echo "   菜单栏 App（PS3Eye-VirtualCam.app）或 ./scripts/uninstall-agent.sh 可停止。"
    exit 0
fi

# 已在运行则提示退出
if pgrep -f "ps3eye-feed$" > /dev/null; then
    echo "⚠️  ps3eye-feed 已在运行（PID $(pgrep -f 'ps3eye-feed$')），先执行 stop.sh"
    exit 1
fi

# 检查 OBS 扩展是否激活
EXT=$(systemextensionsctl list 2>/dev/null | grep "com.obsproject.obs-studio.mac-camera-extension" | grep activated || true)
if [ -z "$EXT" ]; then
    echo "❌ OBS 虚拟摄像头扩展未激活！请先：打开 OBS → Tools → Start Virtual Camera（首次需在系统设置允许扩展）"
    exit 1
fi

mkdir -p logs
nohup ./bin/ps3eye-feed > logs/feed.log 2>&1 &
FEED_PID=$!
echo "✅ ps3eye-feed 已启动 (PID $FEED_PID)"

sleep 3
echo ""
echo "📊 状态："
ps -eo pid,stat,etime,comm | grep "ps3eye-feed" | grep -v grep || echo "⚠️  ps3eye-feed 未运行，看 logs/feed.log"
echo ""
echo "💡 使用：打开 QuickTime/Photo Booth/浏览器等 → 摄像头选 OBS Virtual Camera"
echo "   关闭：./scripts/stop.sh"
