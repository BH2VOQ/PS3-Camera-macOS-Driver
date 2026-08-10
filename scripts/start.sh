#!/bin/bash
# start-ps3eye.sh — 启动 PS3 Eye 虚拟摄像头整套系统
# 组件：
#   1. consumer_watch   — 独立消费者检测进程（每秒写 /tmp/ps3eye_consumer.txt）
#   2. ps3eye-feed      — 抓帧喂 OBS Virtual Camera（无消费者自动停，有消费者自动恢复）
# 前置：OBS 已安装且虚拟摄像头扩展已激活（装 OBS 后 Start Virtual Camera 一次）
set -e
cd "$(dirname "$0")"

# 已在运行则提示退出
if pgrep -f "ps3eye-feed$" > /dev/null; then
    echo "⚠️  ps3eye-feed 已在运行（PID $(pgrep -f 'ps3eye-feed$')），先执行 stop-ps3eye.sh"
    exit 1
fi

# 检查 OBS 扩展是否激活
EXT=$(systemextensionsctl list 2>/dev/null | grep "com.obsproject.obs-studio.mac-camera-extension" | grep activated || true)
if [ -z "$EXT" ]; then
    echo "❌ OBS 虚拟摄像头扩展未激活！请先：打开 OBS → Tools → Start Virtual Camera（首次需在系统设置允许扩展）"
    exit 1
fi

# 启动消费者检测（后台常驻）
nohup ./consumer_watch > watch.log 2>&1 &
WATCH_PID=$!
echo "✅ consumer_watch 已启动 (PID $WATCH_PID)"

# 等待检测文件出现
for i in $(seq 1 10); do
    [ -f /tmp/ps3eye_consumer.txt ] && break
    sleep 0.5
done

# 启动喂帧
nohup ./ps3eye-feed > feed.log 2>&1 &
FEED_PID=$!
echo "✅ ps3eye-feed 已启动 (PID $FEED_PID)"

sleep 3
echo ""
echo "📊 状态："
ps -eo pid,stat,etime,comm | grep -E "ps3eye-feed|consumer_watch" | grep -v grep
echo ""
echo "💡 使用：打开 Photo Booth → 摄像头选 OBS Virtual Camera → 自动出画面"
echo "   关闭：./stop-ps3eye.sh"
