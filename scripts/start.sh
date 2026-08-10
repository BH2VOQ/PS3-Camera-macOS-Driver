#!/bin/bash
# start.sh — 启动 PS3 Eye 虚拟摄像头（ps3eye-feed 单进程，自带消费者检测）
# 行为：无消费者时摄像头待机省电（LED 灭）；有 App 打开 OBS Virtual Camera 时自动抓帧（LED 亮）；
#       App 关闭后 4 秒内自动停止（LED 灭）。消费者存在期间每 4s 有一次 50ms 级眨眼探测（约丢 1 帧，无感）。
# 前置：OBS 已安装且虚拟摄像头扩展已激活（装 OBS 后 Start Virtual Camera 一次）
set -e
cd "$(dirname "$0")/.."

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
echo "💡 使用：打开 QuickTime/Photo Booth/浏览器等 → 摄像头选 OBS Virtual Camera → 自动出画面"
echo "   关闭：./scripts/stop.sh"
