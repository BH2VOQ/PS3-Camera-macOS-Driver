<div align="center">

# 📷 PS3Eye-VirtualCam

**Turn a PlayStation 3 Eye into a system-wide virtual camera on Apple Silicon Macs.**

Capture PS3 Eye frames in userspace with `libusb + PS3EYEDriver + CoreMediaIO`, then feed them into **OBS Virtual Camera** for QuickTime, browsers, conferencing apps, streaming software, and more.

[![Platform](https://img.shields.io/badge/platform-macOS%20Apple%20Silicon-lightgrey?style=flat-square)]()
[![License](https://img.shields.io/badge/license-GPLv2-blue?style=flat-square)](LICENSE)
[![Build](https://img.shields.io/badge/build-macOS%20CI-success?style=flat-square)]()

**English** | [中文](#中文)

</div>

---

# How it works

PS3 Eye has no modern native macOS driver. This project does not install a kernel driver. Instead, it communicates with the OV534/OV772x hardware directly from userspace through `libusb`.

```text
PS3 Eye
  │
  │ USB / libusb
  ▼
PS3EYEDriver
  │
  │ 640×480 @ 30 fps
  ▼
ps3eye-feed
  │
  │ CoreMediaIO / CMSimpleQueue
  │ NV12 frames
  ▼
OBS Camera Extension
  │
  ▼
OBS Virtual Camera
  │
  ├─ QuickTime
  ├─ Browsers
  ├─ Discord / Zoom / Teams
  ├─ OBS
  └─ Other macOS camera apps
```

## 1. PS3 Eye → `ps3eye-feed`

`src/ps3eye-feed.mm` is the main feeder process. It reads frames from PS3 Eye through the bundled PS3EYEDriver and statically linked libusb.

Current capture settings:

- Resolution: `640×480`
- Frame rate: `30 fps`
- Auto gain: enabled
- Auto white balance: enabled
- Brightness: raised for practical macOS use

The feeder converts BGR frames to NV12 before submitting them to CoreMediaIO.

## 2. `ps3eye-feed` → OBS Virtual Camera

This project reuses OBS's Camera Extension instead of shipping a separate macOS Camera Extension.

The feeder:

1. Finds the `OBS Virtual Camera` CoreMediaIO device.
2. Finds its sink stream.
3. Obtains the stream queue through `CMIOStreamCopyBufferQueue()`.
4. Continuously writes PS3 Eye frames into that queue.
5. OBS Camera Extension exposes those frames as a system-visible camera source.

Applications only need to select:

```text
OBS Virtual Camera
```

They do not need to know anything about PS3 Eye or libusb.

## 3. Why manual camera control is used

Earlier versions attempted to detect automatically whether an application was using the virtual camera. Several mechanisms were tested:

- `kCMIODevicePropertyDeviceIsRunningSomewhere`
- `AVCaptureDevice.inUseByAnotherApplication`
- OBS sink queue consumption
- Periodic sink stop/reopen probing

These approaches are not reliable with OBS Camera Extension:

- The feeder's own sink affects CoreMediaIO running state.
- OBS Camera Extension consumes the sink queue even when no final application is actively using the source.
- AVFoundation does not reliably report virtual Camera Extension usage.
- Periodic sink stop/start causes visible interruptions in applications such as QuickTime.

One real symptom was the camera shutting down roughly every ten seconds and then recovering immediately.

The current design therefore prioritizes stability:

> **The feeder stays resident in the background, while the physical PS3 Eye is OFF by default. The user enables or disables the camera manually from the menu bar.**

This avoids false consumer detection from interrupting an active session.

## 4. Why disabling the camera restarts the feeder

The inherited PS3EYEDriver/libusb stop path has a known risk: a transfer callback can enter synchronous transfer cleanup from the libusb event thread, leading to mutex assertions or self-deadlock.

The current implementation therefore avoids frequent `cam->stop()` calls under load.

When the user disables the camera:

```text
Menu bar writes OFF state
      ↓
feeder detects OFF
      ↓
LED is turned off
      ↓
feeder exits through the safe path
      ↓
LaunchAgent relaunches feeder
      ↓
feeder returns to standby with physical camera OFF
```

The background service can remain available without leaving the physical camera streaming all day.

---

# Usage guide

## 1. Requirements

You need:

- Apple Silicon Mac (M1 / M2 / M3 / M4 or newer)
- macOS
- PlayStation 3 Eye camera
- OBS Studio
- Xcode Command Line Tools if building from source

Install Xcode Command Line Tools with:

```bash
xcode-select --install
```

### Prepare OBS Virtual Camera

`OBS Virtual Camera` must already exist on the system.

Install OBS Studio, launch it at least once, and make sure its virtual camera extension is enabled. If macOS asks you to approve the Camera Extension, allow it in System Settings.

---

## 2. Build from source

Clone the repository:

```bash
git clone https://github.com/BH2VOQ/PS3Eye-VirtualCam.git
cd PS3Eye-VirtualCam
```

Build the feeder:

```bash
./build.sh
```

Install the background LaunchAgent:

```bash
./scripts/install-agent.sh
```

The feeder is installed to:

```text
~/Library/Application Support/PS3Eye-VirtualCam/ps3eye-feed
```

Logs are written to:

```text
~/Library/Logs/PS3Eye-VirtualCam/feed.log
```

---

## 3. Build the menu bar app

```bash
./scripts/build-app.sh
```

The menu bar app is responsible for:

- Showing current camera state
- Enabling the physical camera
- Disabling the physical camera
- Opening the feeder log
- Maintaining the feeder and LaunchAgent installation
- Switching the UI language between English and Chinese

The default UI language is English.

---

## 4. Using the menu bar switch

### Default state

After login or installation, the feeder runs in the background but the physical PS3 Eye stays off.

The menu looks similar to:

```text
PS3 Eye: Standby (Camera Off)
Enable Camera
Open Log
Language ▶
Quit Menu Bar App (Background Stays Idle)
```

At this point:

- The PS3 Eye LED should be off.
- The physical camera is not continuously capturing.
- The feeder process stays alive in the background.
- `OBS Virtual Camera` is still provided by OBS Camera Extension.

### Enable the camera

Click:

```text
Enable Camera
```

The feeder then:

1. Opens the OBS Virtual Camera sink.
2. Starts PS3 Eye capture.
3. Turns on the camera LED.
4. Streams `640×480 @ 30 fps` continuously.

Typical log output:

```text
[ps3eye-feed] manual switch ON; starting sink + physical camera
[ps3eye-feed] PS3 Eye streaming 640x480@30 (manual ON)
```

The menu state changes to something like:

```text
PS3 Eye: Streaming
Disable Camera
```

### Use it in another application

Enable the camera first, then select:

```text
OBS Virtual Camera
```

For example in QuickTime Player:

```text
QuickTime Player
→ File
→ New Movie Recording
→ Select OBS Virtual Camera
```

### Disable the camera

When finished, click:

```text
Disable Camera
```

The log should show:

```text
[ps3eye-feed] manual switch OFF; physical camera entering standby
```

The LED turns off. LaunchAgent then relaunches a clean feeder process in standby mode.

### Switch to Chinese

Open:

```text
Language
→ 中文
```

The selected language is stored locally and reused on the next launch.

---

## 5. Update the project

Recommended update flow:

```bash
cd ~/PS3Eye-VirtualCam
git pull
./build.sh
./scripts/install-agent.sh
./scripts/build-app.sh
```

`install-agent.sh` unloads stale LaunchAgent state before registering the current build, which helps avoid `launchctl bootstrap` failures caused by old jobs.

---

# Logs and troubleshooting

## Live log

```bash
tail -f "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

Recent lines:

```bash
tail -n 50 "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

Clear old logs before a clean test:

```bash
: > "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

## Check whether the feeder is running

```bash
pgrep -fl ps3eye-feed
```

## Normal standby log

```text
[ps3eye-feed] starting (manual control mode)
[ps3eye-feed] PS3 Eye standby; manual switch is OFF
```

The LED should be off.

## Normal streaming log

```text
[ps3eye-feed] manual switch ON; starting sink + physical camera
[ps3eye-feed] PS3 Eye streaming 640x480@30 (manual ON)
[ps3eye-feed] 30 frames sent
[ps3eye-feed] 60 frames sent
[ps3eye-feed] 90 frames sent
```

If the frame count continues increasing, the feeder is successfully feeding OBS Virtual Camera.

## QuickTime shows no video

Check the following:

1. The camera is enabled from the menu bar.
2. PS3 Eye LED is on.
3. The log contains `frames sent`.
4. QuickTime is using `OBS Virtual Camera`.
5. OBS Camera Extension is installed and approved by macOS.
6. QuickTime or the target app has camera permission.

## `Bootstrap failed: 5: Input/output error`

The current `scripts/install-agent.sh` includes stronger cleanup for stale launchd state. Usually rerunning it is enough:

```bash
./scripts/install-agent.sh
```

You can also inspect the service with:

```bash
launchctl print "gui/$(id -u)/com.bh2voq.ps3eye-vcam"
```

and validate the plist with:

```bash
plutil -lint "$HOME/Library/LaunchAgents/com.bh2voq.ps3eye-vcam.plist"
```

## Old `pthread_mutex_lock` assertion in the log

The log file is append-only, so an assertion near the top may belong to an older feeder process.

Clear the log and restart the feeder before testing:

```bash
: > "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
launchctl kickstart -k "gui/$(id -u)/com.bh2voq.ps3eye-vcam"
```

---

# Background management

Restart feeder:

```bash
launchctl kickstart -k \
"gui/$(id -u)/com.bh2voq.ps3eye-vcam"
```

Uninstall LaunchAgent:

```bash
./scripts/uninstall-agent.sh
```

---

# Repository layout

| Path | Purpose |
|---|---|
| `src/ps3eye-feed.mm` | PS3 Eye capture, NV12 conversion, CoreMediaIO output, manual state control |
| `src/ps3eye/` | PS3EYEDriver / OV534 userspace driver |
| `src/app/PS3EyeVCMenu.m` | macOS menu bar control app |
| `lib/libusb/` | Static arm64 libusb |
| `build.sh` | Build feeder |
| `scripts/build-app.sh` | Build menu bar app |
| `scripts/install-agent.sh` | Install and register background LaunchAgent |
| `scripts/uninstall-agent.sh` | Remove LaunchAgent |
| `.github/workflows/macos-build.yml` | macOS CI build verification |

---

# Design trade-offs and known limitations

The current priority is:

> **Stability > full automation**

OBS Camera Extension does not expose a reliable source-client count to the external feeder. Automatic shutdown based on indirect signals caused real-world disconnect loops, so the current version deliberately uses a manual switch.

The long-term clean solution would be a dedicated Camera Extension or an explicit client-count IPC channel from the extension to the feeder.

---

# License

GPLv2. See [LICENSE](LICENSE).

This project includes and builds on work from PS3EYEDriver, libusb, and OBS virtual camera components. See the repository license files for details.

---

<a id="中文"></a>

# 中文

<div align="center">

[English](#how-it-works) | **中文**

</div>

## 工作原理

PS3 Eye 没有现代 macOS 原生驱动。本项目不安装内核驱动，而是通过 `libusb + PS3EYEDriver` 在用户态直接读取摄像头，再由 `ps3eye-feed` 把画面转换成 NV12，并通过 CoreMediaIO 送入 OBS Camera Extension。

最终数据链路：

```text
PS3 Eye
  ↓ USB / libusb
PS3EYEDriver
  ↓ 640×480 @ 30 fps
ps3eye-feed
  ↓ CoreMediaIO / NV12
OBS Camera Extension
  ↓
OBS Virtual Camera
  ↓
QuickTime / 浏览器 / 会议软件 / OBS / 其他摄像头 App
```

目标软件只需要选择：

```text
OBS Virtual Camera
```

### 为什么使用手动开关

项目曾经尝试自动判断是否有 App 正在使用虚拟摄像头，包括 CMIO running 状态、AVFoundation 占用状态、sink queue 消费状态和周期性 stop/reopen 探测。

这些方法在 OBS Camera Extension 上都不够可靠，实际曾导致大约每 10 秒自动关闭一次再迅速恢复。

因此当前版本采用：

> **后台 feeder 常驻，物理 PS3 Eye 默认关闭，由菜单栏手动启用或关闭。**

这是目前最稳定的方案。

### 为什么关闭后 feeder 会重启

旧 PS3EYEDriver/libusb 的停止路径存在 transfer callback 自锁风险，所以当前实现避免在负载中频繁调用 `cam->stop()`。

关闭摄像头时会：

```text
菜单栏写入 OFF
  ↓
feeder 检测到 OFF
  ↓
关闭 LED
  ↓
安全退出 feeder
  ↓
LaunchAgent 自动重新拉起
  ↓
回到待机状态
```

## 使用教程

### 前置条件

需要：

- Apple Silicon Mac
- macOS
- PS3 Eye
- OBS Studio
- 从源码构建时需要 Xcode Command Line Tools

安装命令行工具：

```bash
xcode-select --install
```

安装并启动 OBS 至少一次，确保 `OBS Virtual Camera` Camera Extension 已被 macOS 允许。

### 构建和安装

```bash
git clone https://github.com/BH2VOQ/PS3Eye-VirtualCam.git
cd PS3Eye-VirtualCam
./build.sh
./scripts/install-agent.sh
./scripts/build-app.sh
```

后台 feeder 位于：

```text
~/Library/Application Support/PS3Eye-VirtualCam/ps3eye-feed
```

日志位于：

```text
~/Library/Logs/PS3Eye-VirtualCam/feed.log
```

### 菜单栏使用

App 默认显示英文。可通过：

```text
Language
→ 中文
```

切换成中文，语言选择会保存。

默认待机时：

```text
PS3 Eye: 待机（摄像头已关闭）
启用摄像头
打开日志
语言 ▶
退出菜单栏 App（后台保持待机）
```

点击 **启用摄像头** 后：

1. 打开 OBS Virtual Camera sink；
2. 启动 PS3 Eye；
3. LED 亮起；
4. 持续推送 `640×480 @ 30 fps`。

日志：

```text
[ps3eye-feed] manual switch ON; starting sink + physical camera
[ps3eye-feed] PS3 Eye streaming 640x480@30 (manual ON)
```

然后在 QuickTime 等软件中选择：

```text
OBS Virtual Camera
```

使用结束后点击 **关闭摄像头**，PS3 Eye LED 会熄灭，feeder 会通过安全路径退出，并由 LaunchAgent 自动重新拉起进入待机。

### 更新项目

```bash
cd ~/PS3Eye-VirtualCam
git pull
./build.sh
./scripts/install-agent.sh
./scripts/build-app.sh
```

### 查看日志

```bash
tail -f "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

正常待机：

```text
[ps3eye-feed] starting (manual control mode)
[ps3eye-feed] PS3 Eye standby; manual switch is OFF
```

正常推流：

```text
[ps3eye-feed] manual switch ON; starting sink + physical camera
[ps3eye-feed] PS3 Eye streaming 640x480@30 (manual ON)
[ps3eye-feed] 30 frames sent
[ps3eye-feed] 60 frames sent
```

### QuickTime 没有画面

检查：

1. 菜单栏是否已经启用摄像头；
2. PS3 Eye LED 是否亮；
3. 日志是否持续出现 `frames sent`；
4. QuickTime 是否选择 `OBS Virtual Camera`；
5. OBS Camera Extension 是否已允许；
6. macOS 是否给目标 App 相机权限。

### 后台管理

重启 feeder：

```bash
launchctl kickstart -k \
"gui/$(id -u)/com.bh2voq.ps3eye-vcam"
```

卸载：

```bash
./scripts/uninstall-agent.sh
```

## 当前设计取舍

当前优先级是：

> **稳定性 > 全自动**

OBS Camera Extension 没有向外部 feeder 暴露可靠的 source-client count，因此当前版本不再根据间接状态自动关闭正在使用的摄像头。

未来更完整的方案是实现自己的 Camera Extension，或者给 Extension 与 feeder 增加明确的客户端计数 IPC 通道。

## 许可

GPLv2，详见 [LICENSE](LICENSE)。
