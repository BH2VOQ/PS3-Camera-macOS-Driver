<div align="center">

# 📷 PS3Eye-VirtualCam

**让 PS3 Eye 摄像头变成 macOS 系统级虚拟摄像头，供任何 App 使用（人脸追踪 / 直播 / 会议）**

*Turn a PlayStation 3 Eye camera into a system-wide macOS virtual camera for any app (face tracking / streaming / meetings)*

[![Status](https://img.shields.io/badge/状态-BETA%20v0.1.1-yellow?style=for-the-badge)](https://github.com/BH2VOQ/PS3Eye-VirtualCam/releases)
[![License](https://img.shields.io/badge/许可-GPLv2-blue?style=for-the-badge)](LICENSE)
[![Platform](https://img.shields.io/badge/平台-macOS%20Apple%20Silicon-lightgrey?style=for-the-badge)]()
[![Lang](https://img.shields.io/badge/语言-ObjC++%2FC%2B%2B-green?style=for-the-badge)]()

**中文** | [**English**](#english)

</div>

---

<a name="chinese"></a>

# 🌊 中文

> ⚠️ **BETA — v0.1.1-beta**
> 功能可用，画面已人工验收；无消费者自动熄灭已修复。欢迎试用并提 issue。

PS3 Eye（索尼 PlayStation 3 摄像头）是性价比极高的 USB 摄像头（OV534 芯片，支持 640x480@60fps / 320x240@120fps），但在 macOS 上没有任何原生驱动。本项目通过 **OBS 的官方虚拟摄像头扩展** 把它变成系统级摄像头——任何 App（Photo Booth、Zoom、OBS、vtuber 人脸追踪等）都能直接选中使用。

## ✨ 特性

- 🎥 **系统级虚拟摄像头**：基于 OBS mac-virtualcam 扩展，所有 App 可见
- 🔌 **即插即用**：无需付费开发者账号、无需关闭 SIP、无需内核驱动
- 🔋 **无消费者自动熄灭**：没有 App 在用时 LED 自动熄灭、停止供帧；有 App 打开时立即恢复
- 🍎 **Apple Silicon 原生**：arm64 原生编译（静态链接 libusb，无 Homebrew 依赖）
- 🛠 **纯命令行**：一键构建 + 一键启停，无 GUI 依赖

## 🚀 技术路线

```
┌─────────────┐    libusb     ┌──────────────────┐   CMIO   ┌───────────────────┐
│  PS3 Eye    │ ────────────▶ │  ps3eye-feed     │ ───────▶ │ OBS Virtual       │
│  (OV534)    │   USB 抓帧    │  (单进程主程序)   │  NV12 帧 │ Camera 扩展       │
└─────────────┘               └──────────────────┘          │ (系统级虚拟摄像头) │
       640x480@60fps                 │  ▲                    └───────────────────┘
                                     │  │ 自带消费者检测（CMIO）         │
                                     │  │ IDLE: 1s 轮询 gone            ▼
                                     │  │ ACTIVE: 4s 眨眼探测  ┌─────────────────────┐
                                     ▼  │                    │ Photo Booth / Zoom  │
                              (无独立进程)                    │ OBS / vtuber 等 App  │
                                                             └─────────────────────┘
```

**单进程设计（为什么）：**

1. **ps3eye-feed（唯一进程）**：libusb 从 PS3 Eye 抓帧（NV12 640x480），通过 CMIO 往 OBS 虚拟摄像头的 sink 流喂帧；OBS 扩展负责转发为系统级 source 流。
2. **自带消费者检测**：直接查 CMIO `kCMIODevicePropertyDeviceIsRunningSomewhere`，无需独立检测进程：
   - **IDLE（sink 关闭）**：每秒查一次——此时没有自身 sink 干扰，信号干净，消费者到达即开。
   - **ACTIVE（sink 打开）**：每 4s 做「眨眼探测」——关 sink 50ms → 查 gone → 消费者还在就重开（画面仅丢 1 帧，无感）；已离开就熄 LED 回待机。
   - ⚠️ 不能用 AVFoundation `isInUseByAnotherApplication`（OBS 扩展未实现，恒 0）；也不能常驻用 gone（自己的 sink 会把它顶成恒 1，消费者走了不复位）。
3. **省电策略**：摄像头启动后**永不调用 `stop()`**——ps3eye 库的 stop() 在持续负载下会触发 libusb 自锁断言崩溃（写 0xe0 停流 → 在途传输出错 → 回调在传输线程内 close_transfers 与 handle_events 自锁，实测）。空闲时只熄 LED + 关 sink 停止供帧，App 打开瞬间恢复。

**为什么不用其他方案：**

| 方案 | 结论 |
|---|---|
| 自研 system extension（付费开发者账号） | ❌ $99/年，普通用户不划算 |
| 自研用户态 CMIOExtension 虚拟摄像头 | ❌ 需签名/激活，复杂度高 |
| 本地 MJPEG 直接供帧给单个 App | ⚠️ 仅单 App 可用，非系统级 |
| **OBS 官方扩展 + 极简喂帧客户端（本项目）** | ✅ 免费、系统级、无需开发者账号 |

## 🚀 部署

> ⚠️ **由 AI agent 自动构建并复核**：本项目源码与构建脚本由 AI agent 编写与联调。自动构建有边界情况（不同 macOS 版本、不同 Xcode CLT 版本可能影响编译），请按下方检查清单核对。如果你对构建不熟，直接使用 [Releases](https://github.com/BH2VOQ/PS3Eye-VirtualCam/releases) 里的预编译包。

**前置条件：**

- macOS（Apple Silicon，M 系列芯片）
- Xcode 命令行工具：`xcode-select --install`
- **OBS Studio** 已安装，且虚拟摄像头扩展已激活（OBS → Tools → Start Virtual Camera，首次需在系统设置允许扩展）
- PS3 Eye 摄像头（USB-A 转接头插入）

**构建（约 30 秒）：**

```bash
git clone https://github.com/BH2VOQ/PS3Eye-VirtualCam.git
cd PS3Eye-VirtualCam
./build.sh
```

**启动：**

```bash
./scripts/start.sh
```

**使用：** 打开任意 App（Photo Booth / Zoom / OBS / vtuber），摄像头列表选 **OBS Virtual Camera** 即可看到实时画面。

**停止：**

```bash
./scripts/stop.sh
```

## 📁 仓库内容

| 路径 | 说明 |
|---|---|
| `src/ps3eye-feed.mm` | 主程序：libusb 抓帧 → CMIO 喂帧 OBS 虚拟摄像头（自带消费者检测） |
| `src/ps3eye/` | PS3EYEDriver 库源码（OV534 驱动移植） |
| `lib/libusb/` | arm64 静态链接的 libusb 1.0.30 |
| `scripts/start.sh` / `stop.sh` | 一键启停（含 OBS 扩展激活检测） |
| `build.sh` | 一键构建（arm64 原生） |
| `bin/` | 构建产物 |

## ❓ FAQ

| 问题 | 回答 |
|---|---|
| 为什么没有画面？ | 首次使用需在系统设置允许 OBS 扩展，并在 App 里授权相机权限（Photo Booth 会弹窗） |
| 支持 Intel Mac 吗？ | 暂不支持（构建脚本固定 arm64）；Intel 可自行去掉 `-arch arm64` 重编译 |
| 摄像头 LED 不亮？ | 正常——无消费者时自动熄灭省电；打开 App 选中后会自动亮起 |
| 与其他 App 冲突吗？ | 同一时间仅一个 App 能占用虚拟摄像头（系统限制），关闭当前 App 即可切换 |

## 📜 许可 & 🏷 版本

- **GPLv2**（见 [LICENSE](LICENSE)）——基于 [PS3EYEDriver](https://github.com/inspirit/PS3EYEDriver)（MIT + GPLv2 派生）与 [OBS mac-virtualcam](https://github.com/johnboiles/obs-mac-virtualcam)（GPLv2）分支
- 当前版本：**v0.1.1-beta**（画面已人工验收，自动停止修复）
- 不含任何闭源组件；libusb 为 LGPL 静态链接（本项目按 GPLv2 分发，满足链接例外条款）

## 🙏 鸣谢

**inspirit（PS3EYEDriver）** — OV534 驱动移植与 ps3eye 抓帧库。感谢！
**johnboiles（obs-mac-virtualcam）** — OBS 虚拟摄像头扩展。感谢！
**OBS Project** — 虚拟摄像头扩展的官方维护方。感谢！

---

<div align="center">[**English**](#english) · **中文**</div>

<a name="english"></a>

# 🌊 English

> ⚠️ **BETA — v0.1.1-beta**
> Feature-complete, picture human-verified, auto-off fixed. Issues and feedback welcome.

The PlayStation 3 Eye is an excellent cheap USB camera (OV534 chipset, 640x480@60fps / 320x240@120fps) with **no native macOS driver**. This project turns it into a **system-wide virtual camera** via OBS's official virtual camera extension — usable by any app (Photo Booth, Zoom, OBS, vtuber face tracking, etc.).

## ✨ Features

- 🎥 **System-wide virtual camera** based on the OBS mac-virtualcam extension
- 🔌 **Plug & play**: no paid developer account, no SIP disable, no kernel driver
- 🔋 **Auto-off when unused**: LED turns off and frame feeding stops when no app consumes the camera; resumes instantly on demand
- 🍎 **Apple Silicon native**: arm64 build, statically-linked libusb (no Homebrew dependency)
- 🛠 **CLI only**: one-command build + one-command start/stop

## 🚀 Architecture

```
┌─────────────┐    libusb     ┌──────────────────┐   CMIO   ┌───────────────────┐
│  PS3 Eye    │ ────────────▶ │  ps3eye-feed     │ ───────▶ │ OBS Virtual       │
│  (OV534)    │   USB frames  │  (single process)│  NV12    │ Camera extension  │
└─────────────┘               └──────────────────┘          └───────────────────┘
       640x480@60fps                 │  ▲                          │
                                     │  │ built-in consumer        ▼
                                     │  │ detection (CMIO)   ┌─────────────────────┐
                                     ▼  │ IDLE: poll 1s       │ Photo Booth / Zoom  │
                              (no watchdog      │ ACTIVE: 4s blink │ OBS / vtuber apps   │
                               process)         ▼                  └─────────────────────┘
```

**Single-process design (why):**

1. **ps3eye-feed (the only process)**: grabs NV12 640x480 frames via libusb and pushes them into the OBS virtual camera's sink stream through CMIO.
2. **Built-in consumer detection**: queries CMIO `kCMIODevicePropertyDeviceIsRunningSomewhere` directly — no separate watchdog process:
   - **IDLE (sink closed)**: poll every second — no self-sink interference, clean signal; opens as soon as a consumer arrives.
   - **ACTIVE (sink open)**: a 50ms "blink probe" every 4s — close sink → query `gone` → reopen if the consumer is still there (only 1 frame dropped, imperceptible); if gone, LED off and back to idle.
   - ⚠️ `AVCaptureDevice.isInUseByAnotherApplication` is not usable (the OBS extension never implements it — always 0); a permanent `gone` check is also unusable (our own sink keeps it at 1 forever, even after the consumer leaves).
3. **Power strategy**: after first start the camera **never calls `stop()`** — the ps3eye library's stop() self-deadlocks under sustained load (writing 0xe0 to stop the stream makes in-flight transfers error out; the callback then calls close_transfers() from the transfer thread while inside libusb_handle_events → assertion crash, verified). Idle = LED off + sink closed (no frames pushed); resumes instantly when an app opens the camera.

**Why not other approaches:**

| Approach | Verdict |
|---|---|
| Custom system extension ($99/yr dev account) | ❌ Not worth it for regular users |
| Custom user-space CMIOExtension virtual camera | ❌ Signing/activation complexity |
| Local MJPEG to a single app | ⚠️ Not system-wide |
| **OBS official extension + minimal feeder (this project)** | ✅ Free, system-wide, no dev account |

## 🚀 Deployment

> ⚠️ **Built and verified by an AI agent.** Source and build scripts were authored and debugged by an AI agent; edge cases may exist across macOS/Xcode CLT versions. Use the checklist below, or grab a prebuilt binary from [Releases](https://github.com/BH2VOQ/PS3Eye-VirtualCam/releases) if you don't want to build.

**Prerequisites:**

- macOS on Apple Silicon (M-series)
- Xcode Command Line Tools: `xcode-select --install`
- **OBS Studio** installed with the virtual camera extension activated (OBS → Tools → Start Virtual Camera; allow the extension in System Settings on first run)
- PS3 Eye camera connected via USB-A adapter

**Build (~30s):**

```bash
git clone https://github.com/BH2VOQ/PS3Eye-VirtualCam.git
cd PS3Eye-VirtualCam
./build.sh
```

**Start:**

```bash
./scripts/start.sh
```

**Use:** open any app (Photo Booth / Zoom / OBS / vtuber), pick **OBS Virtual Camera** from the camera list.

**Stop:**

```bash
./scripts/stop.sh
```

## 📁 Repository Contents

| Path | Description |
|---|---|
| `src/ps3eye-feed.mm` | Main feeder: libusb capture → CMIO frames into OBS virtual camera (built-in consumer detection) |
| `src/ps3eye/` | PS3EYEDriver library source (OV534 driver port) |
| `lib/libusb/` | arm64 static libusb 1.0.30 |
| `scripts/start.sh` / `stop.sh` | One-command start/stop (with OBS extension check) |
| `build.sh` | One-command build (arm64 native) |
| `bin/` | Build output |

## ❓ FAQ

| Question | Answer |
|---|---|
| No picture? | First run: allow the OBS extension in System Settings and grant camera permission in your app (Photo Booth prompts) |
| Intel Mac support? | Not yet (build script is arm64-only); remove `-arch arm64` and rebuild if you want |
| LED not on? | Normal — auto-off when unused; it lights up when an app selects the camera |
| Conflicts with other apps? | Only one app can use the virtual camera at a time (system limit); close the current app to switch |

## 📜 License & 🏷 Version

- **GPLv2** (see [LICENSE](LICENSE)) — forked from [PS3EYEDriver](https://github.com/inspirit/PS3EYEDriver) (MIT + GPLv2 derived) and [OBS mac-virtualcam](https://github.com/johnboiles/obs-mac-virtualcam) (GPLv2)
- Current version: **v0.1.1-beta** (picture human-verified, auto-off fix included)
- No closed-source components; libusb is LGPL statically linked (distributed under GPLv2 per the linking exception)

## 🙏 Acknowledgements

**inspirit (PS3EYEDriver)** — OV534 driver port and ps3eye capture library. Thank you!
**johnboiles (obs-mac-virtualcam)** — OBS virtual camera extension. Thank you!
**OBS Project** — official maintainers of the virtual camera extension. Thank you!

---

<div align="center">[**中文**](#chinese) · **English**</div>
