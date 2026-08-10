#!/bin/bash
# stop-ps3eye.sh — 停止 PS3 Eye 虚拟摄像头整套系统
cd "$(dirname "$0")"

pkill -f "ps3eye-feed$" 2>/dev/null && echo "✅ ps3eye-feed 已停止" || echo "ℹ️  ps3eye-feed 未在运行"
pkill -f "consumer_watch" 2>/dev/null && echo "✅ consumer_watch 已停止" || echo "ℹ️  consumer_watch 未在运行"
rm -f /tmp/ps3eye_consumer.txt

sleep 1
REMAIN=$(ps -eo comm | grep -E "ps3eye-feed|consumer_watch" | grep -v grep | head -3)
if [ -z "$REMAIN" ]; then
    echo "✅ 全部清理完毕"
else
    echo "⚠️  残留进程：$REMAIN（等内核清理，U 态不可杀）"
fi
