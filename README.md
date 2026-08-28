<div align="center">

# 📷 PS3Eye-VirtualCam

**在 Apple Silicon Mac 上把 PlayStation 3 Eye 变成系统级虚拟摄像头。**

通过用户态 `libusb + PS3EYEDriver + CoreMediaIO` 抓取 PS3 Eye 画面，再把视频帧送入 **OBS Virtual Camera**，供 QuickTime、浏览器、会议软件、直播软件等使用。

[![Platform](https://img.shields.io/badge/platform-macOS%20Apple%20Silicon-lightgrey?style=flat-square)]()
[![License](https://img.shields.io/badge/license-GPLv2-blue?style=flat-square)](LICENSE)
[![Build](https://img.shields.io/badge/build-macOS%20CI-success?style=flat-square)]()

</div>

---

## 项目是怎么工作的

PS3 Eye 本身没有现代 macOS 原生驱动。本项目不安装内核驱动，而是在用户态直接通过 `libusb` 与 PS3 Eye 的 OV534/OV772x 硬件通信。

整体数据链路如下：

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
  │ NV12 视频帧
  ▼
OBS Camera Extension
  │
  ▼
OBS Virtual Camera
  │
  ├─ QuickTime
  ├─ 浏览器
  ├─ Discord / Zoom / Teams
  ├─ OBS
  └─ 其他支持 macOS 摄像头的 App
```

### 1. PS3 Eye → `ps3eye-feed`

`src/ps3eye-feed.mm` 是核心 feeder。

它通过仓库中的 PS3EYEDriver 和静态链接的 libusb 直接读取 PS3 Eye：

- 分辨率：`640×480`
- 帧率：`30 fps`
- 自动增益：开启
- 自动白平衡：开启
- 亮度：针对 macOS 使用场景做了提高

摄像头输出的 BGR 图像会在 feeder 中转换成 NV12，再提交给 CoreMediaIO。

### 2. `ps3eye-feed` → OBS Virtual Camera

本项目目前复用 OBS 官方 Camera Extension，而不是自己再实现一整套 macOS Camera Extension。

`ps3eye-feed` 会：

1. 找到系统中的 `OBS Virtual Camera` CoreMediaIO 设备；
2. 找到它的 sink stream；
3. 通过 `CMIOStreamCopyBufferQueue()` 获取帧队列；
4. 将 PS3 Eye 的视频帧持续写入该队列；
5. OBS Camera Extension 再把这些帧转发成系统可见的虚拟摄像头 source stream。

因此最终使用摄像头的软件不需要知道 PS3 Eye，也不需要支持 libusb，只需要选择：

```text
OBS Virtual Camera
```

### 3. 为什么现在使用“手动开关”

早期版本尝试过自动判断“是否有 App 正在使用虚拟摄像头”，包括：

- `kCMIODevicePropertyDeviceIsRunningSomewhere`
- `AVCaptureDevice.inUseByAnotherApplication`
- OBS sink queue 是否被消费
- 周期性关闭/reopen sink 进行探测

这些方法在 OBS Camera Extension 上都存在边界问题：

- feeder 自己启动 sink 后，也会影响 CMIO 的 running 状态；
- OBS Extension 本身会消费 sink queue，不能代表真正有最终用户；
- AVFoundation 对虚拟 Camera Extension 的使用状态并不可靠；
- 周期性 Stop/Start sink 会让 QuickTime 等应用看到短暂断流。

实际表现就是曾经出现过“约 10 秒关闭一次，然后迅速恢复”的问题。

因此当前版本采用更稳定的策略：

> **后台 feeder 常驻，但物理 PS3 Eye 默认关闭；由用户在菜单栏手动启用或关闭摄像头。**

这样可以避免任何错误的消费者检测导致正在使用中的摄像头被自动关闭。

### 4. 为什么关闭摄像头时会重启 feeder

PS3EYEDriver 的旧 libusb 停流路径存在一个已知风险：传输 callback 中可能进入同步 transfer 清理，导致 libusb 事件线程发生 mutex assertion / self-deadlock。

因此当前版本不会在高负载运行中频繁调用危险的 `cam->stop()`。

关闭摄像头时采用：

```text
菜单栏写入 OFF 状态
      ↓
feeder 检测到 OFF
      ↓
关闭 LED
      ↓
进程安全退出（跳过危险析构路径）
      ↓
LaunchAgent 自动重新拉起 feeder
      ↓
重新进入“待机、物理摄像头关闭”状态
```

这也是为什么后台 feeder 可以长期存在，但 PS3 Eye 本体并不需要一直工作。

---

# 使用教程

## 1. 前置条件

需要：

- Apple Silicon Mac（M1 / M2 / M3 / M4 等）
- macOS
- PS3 Eye 摄像头
- OBS Studio
- Xcode Command Line Tools（如果从源码构建）

安装 Xcode Command Line Tools：

```bash
xcode-select --install
```

### OBS Virtual Camera

必须先让系统中存在 `OBS Virtual Camera`。

安装 OBS Studio 后，至少启动一次 OBS，并确认虚拟摄像头扩展已经在系统中启用。

如果 macOS 要求允许 Camera Extension，请在系统设置中允许。

---

## 2. 从源码安装

克隆仓库：

```bash
git clone https://github.com/BH2VOQ/PS3Eye-VirtualCam.git
cd PS3Eye-VirtualCam
```

构建 feeder：

```bash
./build.sh
```

安装后台 LaunchAgent：

```bash
./scripts/install-agent.sh
```

成功时会看到类似：

```text
✅ LaunchAgent 已安装并常驻运行（开机自启）
```

后台程序安装到：

```text
~/Library/Application Support/PS3Eye-VirtualCam/ps3eye-feed
```

日志位于：

```text
~/Library/Logs/PS3Eye-VirtualCam/feed.log
```

---

## 3. 构建菜单栏 App

```bash
./scripts/build-app.sh
```

菜单栏 App 负责：

- 显示当前状态；
- 启用摄像头；
- 关闭摄像头；
- 打开日志；
- 自动维护后台 feeder 和 LaunchAgent。

首次运行 App 时，它会把当前打包的 feeder 安装/更新到 Application Support，并刷新 LaunchAgent。

---

## 4. 菜单栏怎么用

当前版本推荐直接使用菜单栏开关。

### 默认状态

登录 macOS 或安装完成后，feeder 会在后台运行，但 PS3 Eye 默认关闭。

菜单栏状态类似：

```text
PS3 Eye: 待机（已关闭）
启用摄像头
打开日志
退出菜单栏（后台保持待机）
```

此时：

- PS3 Eye LED 应该是灭的；
- 物理摄像头不持续采集；
- 后台 feeder 保持运行；
- `OBS Virtual Camera` 仍由 OBS Camera Extension 提供给系统。

### 启用摄像头

点击：

```text
启用摄像头
```

feeder 检测到手动开关为 ON 后会：

1. 打开 OBS Virtual Camera sink；
2. 启动 PS3 Eye；
3. 点亮 LED；
4. 持续推送 `640×480 @ 30fps` 画面。

日志会出现：

```text
[ps3eye-feed] manual switch ON; starting sink + physical camera
[ps3eye-feed] PS3 Eye streaming 640x480@30 (manual ON)
```

菜单栏状态会变为：

```text
PS3 Eye: 推流中
关闭摄像头
```

### 在其他 App 中使用

先在菜单栏点击 **启用摄像头**，然后在目标软件里选择：

```text
OBS Virtual Camera
```

例如 QuickTime：

```text
QuickTime Player
→ 文件
→ 新建影片录制
→ 摄像头选择 OBS Virtual Camera
```

### 关闭摄像头

使用结束后，在菜单栏点击：

```text
关闭摄像头
```

日志会出现：

```text
[ps3eye-feed] manual switch OFF; physical camera entering standby
```

PS3 Eye LED 会熄灭。

LaunchAgent 随后重新拉起一个新的 feeder，并停在待机状态。

---

## 5. 更新项目

更新源码：

```bash
cd ~/PS3Eye-VirtualCam
git pull
```

重新构建：

```bash
./build.sh
```

重新安装后台 feeder：

```bash
./scripts/install-agent.sh
```

如果也使用菜单栏 App，再重新构建：

```bash
./scripts/build-app.sh
```

推荐的完整更新流程：

```bash
cd ~/PS3Eye-VirtualCam
git pull
./build.sh
./scripts/install-agent.sh
./scripts/build-app.sh
```

`install-agent.sh` 会主动卸载旧的 LaunchAgent 状态，再注册新版本，避免 macOS `launchctl bootstrap` 因残留任务状态失败。

---

# 日志与排查

## 查看实时日志

```bash
tail -f "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

查看最近 50 行：

```bash
tail -n 50 "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

清空旧日志后重新测试：

```bash
: > "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

---

## 检查 feeder 是否运行

```bash
pgrep -fl ps3eye-feed
```

正常会看到类似：

```text
44958 /Users/yourname/Library/Application Support/PS3Eye-VirtualCam/ps3eye-feed
```

---

## 正常待机日志

```text
[ps3eye-feed] starting (manual control mode)
[ps3eye-feed] PS3 Eye standby; manual switch is OFF
```

此时 LED 应该熄灭。

---

## 正常启用日志

```text
[ps3eye-feed] manual switch ON; starting sink + physical camera
[ps3eye-feed] PS3 Eye streaming 640x480@30 (manual ON)
[ps3eye-feed] 30 frames sent
[ps3eye-feed] 60 frames sent
[ps3eye-feed] 90 frames sent
```

只要帧数持续增长，说明 feeder 正在正常向 OBS Virtual Camera 推流。

---

## QuickTime 没画面

依次检查：

1. 菜单栏是否已经点击 **启用摄像头**；
2. PS3 Eye LED 是否亮起；
3. 日志是否出现 `frames sent`；
4. QuickTime 是否选择了 `OBS Virtual Camera`；
5. OBS Camera Extension 是否已经安装并被 macOS 允许；
6. macOS 是否给 QuickTime/目标 App 相机权限。

---

## `Bootstrap failed: 5: Input/output error`

新版 `scripts/install-agent.sh` 已经包含更完整的旧任务清理逻辑。

一般重新执行即可：

```bash
./scripts/install-agent.sh
```

如果仍然失败，可以检查：

```bash
launchctl print "gui/$(id -u)/com.bh2voq.ps3eye-vcam"
```

以及：

```bash
plutil -lint "$HOME/Library/LaunchAgents/com.bh2voq.ps3eye-vcam.plist"
```

---

## 日志里看到旧的 `pthread_mutex_lock` assertion

日志文件是追加写入的，所以顶部的 assertion 不一定属于当前 feeder 进程。

先清空日志再重新测试：

```bash
: > "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
launchctl kickstart -k "gui/$(id -u)/com.bh2voq.ps3eye-vcam"
```

再观察新的日志。

---

# 后台管理

## 手动重启 feeder

```bash
launchctl kickstart -k \
"gui/$(id -u)/com.bh2voq.ps3eye-vcam"
```

## 卸载 LaunchAgent

```bash
./scripts/uninstall-agent.sh
```

---

# 项目结构

| 路径 | 作用 |
|---|---|
| `src/ps3eye-feed.mm` | PS3 Eye 抓帧、NV12 转换、CoreMediaIO 推流、手动状态控制 |
| `src/ps3eye/` | PS3EYEDriver / OV534 用户态驱动 |
| `src/app/PS3EyeVCMenu.m` | macOS 菜单栏控制 App |
| `lib/libusb/` | arm64 静态 libusb |
| `build.sh` | 构建 feeder |
| `scripts/build-app.sh` | 构建菜单栏 App |
| `scripts/install-agent.sh` | 安装并注册后台 LaunchAgent |
| `scripts/uninstall-agent.sh` | 卸载 LaunchAgent |
| `.github/workflows/macos-build.yml` | macOS CI 构建验证 |

---

# 当前设计取舍与已知限制

### 当前优先级：稳定性 > 全自动

目前已经确认：OBS Camera Extension 没有向外部 feeder 暴露一个可靠的“当前 source 客户端数量”接口。

因此当前版本不会再尝试根据不可靠信号自动关机。

也就是说：

- **开启由用户手动控制；**
- **关闭由用户手动控制；**
- 一旦开启，本次会话不会因为错误的消费者检测而周期性掉线。

这是当前最稳定的工作模式。

### 为什么不直接自己实现 Camera Extension

完全自研 Camera Extension 可以在 extension 内部直接获得客户端生命周期，因此理论上可以实现真正可靠的自动开关。

但它会明显增加：

- Camera Extension 工程复杂度；
- 签名与安装复杂度；
- macOS 不同版本兼容成本；
- 发布和维护成本。

当前项目优先复用 OBS 官方扩展，以保持部署简单。

---

# 构建验证

仓库包含 macOS GitHub Actions：

```text
.github/workflows/macos-build.yml
```

CI 会验证：

```bash
./build.sh
./scripts/build-app.sh
```

这能覆盖编译级回归，但无法替代真实 PS3 Eye USB 硬件测试。

---

# License

本项目按 GPLv2 分发，详见：

- [`LICENSE`](LICENSE)
- [`LICENSE-PS3EYEDriver`](LICENSE-PS3EYEDriver)

项目使用或参考：

- PS3EYEDriver
- libusb
- OBS macOS Virtual Camera / Camera Extension

感谢相关开源项目的工作。
