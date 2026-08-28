# 📷 PS3Eye-VirtualCam

[English](README.md) | **简体中文**

在 Apple Silicon Mac 上把 PlayStation 3 Eye 变成系统级虚拟摄像头。

本项目通过 `libusb + PS3EYEDriver + CoreMediaIO` 在用户态读取 PS3 Eye，并把视频帧送入 **OBS Virtual Camera**，供 QuickTime、浏览器、会议软件、直播软件等使用。

## 工作原理

```text
PS3 Eye
  │ USB / libusb
  ▼
PS3EYEDriver
  │ 640×480 @ 30 fps
  ▼
ps3eye-feed
  │ CoreMediaIO / CMSimpleQueue
  │ NV12 视频帧
  ▼
OBS Camera Extension
  ▼
OBS Virtual Camera
  ├─ QuickTime
  ├─ 浏览器
  ├─ Discord / Zoom / Teams
  ├─ OBS
  └─ 其他 macOS 摄像头 App
```

`src/ps3eye-feed.mm` 是核心 feeder。它通过 PS3EYEDriver 和静态链接的 libusb 读取 PS3 Eye，当前使用 `640×480 @ 30 fps`，启用自动增益和自动白平衡，并把 BGR 图像转换成 NV12 后送入 CoreMediaIO。

本项目复用 OBS 的 Camera Extension，而不是自行安装内核驱动或完整重写系统摄像头扩展。目标 App 最终只需要选择：

```text
OBS Virtual Camera
```

### 为什么现在使用手动开关

早期版本尝试过自动判断“是否有 App 正在使用虚拟摄像头”，包括：

- `kCMIODevicePropertyDeviceIsRunningSomewhere`
- `AVCaptureDevice.inUseByAnotherApplication`
- OBS sink queue 是否被消费
- 周期性关闭/重新打开 sink 探测

这些信号在 OBS Camera Extension 上都不够可靠，曾经实际造成约每 10 秒关闭一次然后迅速恢复的断流问题。

因此当前版本优先稳定性：

> **后台 feeder 常驻；物理 PS3 Eye 默认关闭；由用户在菜单栏手动启用或关闭摄像头。**

### 为什么关闭摄像头时 feeder 会重启

旧 PS3EYEDriver/libusb 的停止路径存在 transfer callback 自锁风险，因此当前实现避免在负载中频繁调用 `cam->stop()`。

关闭摄像头时采用：

```text
菜单栏写入 OFF
  ↓
feeder 检测到 OFF
  ↓
关闭 LED
  ↓
feeder 通过安全路径退出
  ↓
LaunchAgent 自动重新拉起
  ↓
重新进入待机状态
```

这样可以关闭物理摄像头，又避免高风险的 libusb stop 路径。

---

# 使用教程

## 1. 前置条件

需要：

- Apple Silicon Mac（M1 / M2 / M3 / M4 等）
- macOS
- PS3 Eye 摄像头
- OBS Studio
- 从源码构建时需要 Xcode Command Line Tools

安装命令行工具：

```bash
xcode-select --install
```

安装 OBS Studio，并至少启动一次 OBS，确保 `OBS Virtual Camera` Camera Extension 已被 macOS 允许。

## 2. 从源码构建并安装

```bash
git clone https://github.com/BH2VOQ/PS3Eye-VirtualCam.git
cd PS3Eye-VirtualCam
./build.sh
./scripts/install-agent.sh
./scripts/build-app.sh
```

后台 feeder 安装到：

```text
~/Library/Application Support/PS3Eye-VirtualCam/ps3eye-feed
```

日志位于：

```text
~/Library/Logs/PS3Eye-VirtualCam/feed.log
```

## 3. 菜单栏 App

菜单栏 App 默认使用英文，可在：

```text
Language
→ 中文
```

切换为中文，语言选择会保存在本机。

默认待机状态：

```text
PS3 Eye: 待机（摄像头已关闭）
启用摄像头
打开日志
语言 ▶
退出菜单栏 App（后台保持待机）
```

此时 PS3 Eye LED 应该熄灭，物理摄像头不持续采集，但后台 feeder 保持运行。

### 启用摄像头

点击：

```text
启用摄像头
```

feeder 会打开 OBS Virtual Camera sink、启动 PS3 Eye、点亮 LED，并以 `640×480 @ 30 fps` 持续推流。

正常日志：

```text
[ps3eye-feed] manual switch ON; starting sink + physical camera
[ps3eye-feed] PS3 Eye streaming 640x480@30 (manual ON)
[ps3eye-feed] 30 frames sent
[ps3eye-feed] 60 frames sent
```

### 在 QuickTime 中使用

```text
QuickTime Player
→ 文件
→ 新建影片录制
→ 摄像头选择 OBS Virtual Camera
```

### 关闭摄像头

使用结束后点击：

```text
关闭摄像头
```

日志会出现：

```text
[ps3eye-feed] manual switch OFF; physical camera entering standby
```

LED 熄灭，LaunchAgent 会重新拉起一个新的待机 feeder。

## 4. 更新项目

推荐完整更新流程：

```bash
cd ~/PS3Eye-VirtualCam
git pull
./build.sh
./scripts/install-agent.sh
./scripts/build-app.sh
```

## 5. 查看日志

实时查看：

```bash
tail -f "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

最近 50 行：

```bash
tail -n 50 "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

清空旧日志：

```bash
: > "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

检查 feeder：

```bash
pgrep -fl ps3eye-feed
```

## 6. 常见问题

### QuickTime 没有画面

依次检查：

1. 菜单栏是否已经启用摄像头；
2. PS3 Eye LED 是否亮起；
3. 日志是否持续出现 `frames sent`；
4. QuickTime 是否选择了 `OBS Virtual Camera`；
5. OBS Camera Extension 是否已安装并允许；
6. 目标 App 是否有相机权限。

### `Bootstrap failed: 5: Input/output error`

新版 `scripts/install-agent.sh` 已包含旧 LaunchAgent 状态清理逻辑。通常重新执行即可：

```bash
./scripts/install-agent.sh
```

也可以检查：

```bash
launchctl print "gui/$(id -u)/com.bh2voq.ps3eye-vcam"
plutil -lint "$HOME/Library/LaunchAgents/com.bh2voq.ps3eye-vcam.plist"
```

### 日志里看到旧的 `pthread_mutex_lock` assertion

日志是追加写入的，顶部 assertion 可能属于旧进程。先清空日志再重新测试：

```bash
: > "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
launchctl kickstart -k "gui/$(id -u)/com.bh2voq.ps3eye-vcam"
```

---

# 后台管理

重启 feeder：

```bash
launchctl kickstart -k \
"gui/$(id -u)/com.bh2voq.ps3eye-vcam"
```

卸载 LaunchAgent：

```bash
./scripts/uninstall-agent.sh
```

---

# 项目结构

| 路径 | 作用 |
|---|---|
| `src/ps3eye-feed.mm` | PS3 Eye 抓帧、NV12 转换、CoreMediaIO 输出、手动状态控制 |
| `src/ps3eye/` | PS3EYEDriver / OV534 用户态驱动 |
| `src/app/PS3EyeVCMenu.m` | macOS 菜单栏控制 App |
| `lib/libusb/` | arm64 静态 libusb |
| `build.sh` | 构建 feeder |
| `scripts/build-app.sh` | 构建菜单栏 App |
| `scripts/install-agent.sh` | 安装并注册 LaunchAgent |
| `scripts/uninstall-agent.sh` | 卸载 LaunchAgent |
| `.github/workflows/macos-build.yml` | macOS CI 构建验证 |

---

# 当前设计取舍

当前优先级：

> **稳定性 > 全自动**

OBS Camera Extension 没有向外部 feeder 暴露可靠的 source-client 数量，因此当前版本故意采用手动开关，避免错误的自动检测再次打断正在使用的画面。

长期更彻底的方案，是使用独立 Camera Extension，或者由扩展显式向 feeder 提供客户端数量 IPC。

# License

GPLv2。详见 [LICENSE](LICENSE)。