<div align="center">

# 📷 PS3 Camera macOS Driver

**Use a PlayStation 3 Eye as a system-wide camera on Apple Silicon Macs.**

A userspace macOS camera bridge built with `libusb + PS3EYEDriver + CoreMediaIO`, feeding frames into **OBS Virtual Camera** for QuickTime, browsers, conferencing apps, streaming software, and more.

[![Platform](https://img.shields.io/badge/platform-macOS%20Apple%20Silicon-lightgrey?style=flat-square)]()
[![License](https://img.shields.io/badge/license-GPLv2-blue?style=flat-square)](LICENSE)
[![Build](https://img.shields.io/badge/build-macOS%20CI-success?style=flat-square)]()

**English** | [简体中文](README.zh-CN.md)

</div>

---

## How it works

The PS3 Eye has no modern native macOS driver. This project communicates with the OV534/OV772x hardware directly from userspace instead of installing a kernel extension.

```text
PS3 Eye
  │ USB / libusb
  ▼
PS3EYEDriver
  │ 640×480 @ 30 fps
  ▼
ps3eye-feed
  │ BGR → NV12
  │ CoreMediaIO / CMSimpleQueue
  ▼
OBS Camera Extension
  ▼
OBS Virtual Camera
  ├─ QuickTime
  ├─ Browsers
  ├─ Discord / Zoom / Teams
  ├─ OBS
  └─ Other macOS camera apps
```

`src/ps3eye-feed.mm` is the core feeder. It captures PS3 Eye frames through the bundled PS3EYEDriver and statically linked libusb, converts BGR frames to NV12, and pushes them into the OBS Camera Extension sink stream through CoreMediaIO.

Applications only need to select:

```text
OBS Virtual Camera
```

### Capture defaults

- Resolution: `640×480`
- Frame rate: `30 fps`
- Auto gain: enabled
- Auto white balance: enabled
- Brightness: adjusted for practical macOS use

## Why manual camera control is used

Earlier versions attempted automatic consumer detection using CoreMediaIO running state, AVFoundation usage state, sink queue activity, and periodic sink stop/reopen probing.

Those signals are not reliable enough with OBS Camera Extension. In real use they caused the camera to shut down about every ten seconds and immediately reconnect.

The current design therefore prioritizes stability:

> **The feeder stays resident in the background, while the physical PS3 Eye is OFF by default. You enable or disable the camera manually from the menu bar.**

## Why disabling the camera restarts the feeder

The inherited PS3EYEDriver/libusb stop path has a known risk where transfer cleanup can run from the libusb event thread and trigger mutex assertions or a self-deadlock.

To avoid repeatedly calling the risky `cam->stop()` path under load, disabling the camera works like this:

```text
Menu bar writes OFF
      ↓
feeder detects OFF
      ↓
LED turns off
      ↓
feeder exits through the safe path
      ↓
LaunchAgent relaunches feeder
      ↓
standby with the physical camera OFF
```

---

# Usage

## 1. Requirements

You need:

- Apple Silicon Mac
- macOS
- PlayStation 3 Eye camera
- OBS Studio
- Xcode Command Line Tools when building from source

Install the command line tools with:

```bash
xcode-select --install
```

Install OBS Studio, launch it at least once, and make sure **OBS Virtual Camera** is enabled and approved by macOS.

## 2. Build and install

```bash
git clone https://github.com/BH2VOQ/PS3Eye-VirtualCam.git
cd PS3Eye-VirtualCam
./build.sh
./scripts/install-agent.sh
./scripts/build-app.sh
```

The background feeder is installed to:

```text
~/Library/Application Support/PS3Eye-VirtualCam/ps3eye-feed
```

Logs are written to:

```text
~/Library/Logs/PS3Eye-VirtualCam/feed.log
```

The legacy internal support path and LaunchAgent identifiers are intentionally kept for upgrade compatibility.

## 3. Menu bar app

The menu bar app defaults to English. You can switch languages from:

```text
Language
→ 中文
```

A typical standby menu is:

```text
PS3 Eye: Standby (Camera Off)
Enable Camera
Open Log
Language ▶
Quit Menu Bar App (Background Stays Idle)
```

### Enable the camera

Click `Enable Camera`. The feeder starts the OBS sink, starts PS3 Eye capture, turns on the LED, and streams at `640×480 @ 30 fps`.

Expected log output:

```text
[ps3eye-feed] manual switch ON; starting sink + physical camera
[ps3eye-feed] PS3 Eye streaming 640x480@30 (manual ON)
[ps3eye-feed] 30 frames sent
[ps3eye-feed] 60 frames sent
```

### Use it in QuickTime

```text
QuickTime Player
→ File
→ New Movie Recording
→ Select OBS Virtual Camera
```

### Disable the camera

Click `Disable Camera`.

Expected log output:

```text
[ps3eye-feed] manual switch OFF; physical camera entering standby
```

The LED turns off and LaunchAgent relaunches a clean feeder process in standby mode.

## 4. Update

Recommended update flow:

```bash
cd ~/PS3Eye-VirtualCam
git pull
./build.sh
./scripts/install-agent.sh
./scripts/build-app.sh
```

---

# Logs and troubleshooting

Live log:

```bash
tail -f "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

Recent log lines:

```bash
tail -n 50 "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

Clear old logs before a clean test:

```bash
: > "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
```

Check the feeder process:

```bash
pgrep -fl ps3eye-feed
```

### QuickTime shows no video

Check that:

1. The camera is enabled from the menu bar.
2. The PS3 Eye LED is on.
3. The log continuously prints `frames sent`.
4. QuickTime is using `OBS Virtual Camera`.
5. OBS Camera Extension is installed and approved by macOS.
6. The target application has camera permission.

### `Bootstrap failed: 5: Input/output error`

Retry:

```bash
./scripts/install-agent.sh
```

Inspect launchd state with:

```bash
launchctl print "gui/$(id -u)/com.bh2voq.ps3eye-vcam"
plutil -lint "$HOME/Library/LaunchAgents/com.bh2voq.ps3eye-vcam.plist"
```

### Old `pthread_mutex_lock` assertion in the log

The log is append-only, so an assertion near the top may belong to an older feeder process. Clear the log and restart before testing:

```bash
: > "$HOME/Library/Logs/PS3Eye-VirtualCam/feed.log"
launchctl kickstart -k "gui/$(id -u)/com.bh2voq.ps3eye-vcam"
```

---

# Background management

Restart the feeder:

```bash
launchctl kickstart -k \
"gui/$(id -u)/com.bh2voq.ps3eye-vcam"
```

Uninstall the LaunchAgent:

```bash
./scripts/uninstall-agent.sh
```

---

# Repository layout

| Path | Purpose |
|---|---|
| `src/ps3eye-feed.mm` | PS3 Eye capture, NV12 conversion, CoreMediaIO output, manual state control |
| `src/ps3eye/` | PS3EYEDriver / OV534 userspace driver |
| `src/app/PS3EyeVCMenu.m` | macOS menu bar controller |
| `lib/libusb/` | Static arm64 libusb |
| `build.sh` | Build the feeder |
| `scripts/build-app.sh` | Build the menu bar app |
| `scripts/install-agent.sh` | Install and register the LaunchAgent |
| `scripts/uninstall-agent.sh` | Remove the LaunchAgent |
| `.github/workflows/macos-build.yml` | macOS CI build verification |

---

# Current design trade-off

> **Stability > full automation**

OBS Camera Extension does not expose a reliable source-client count to the external feeder. Automatic shutdown based on indirect signals caused real disconnect loops, so the current version intentionally uses a manual switch.

A future fully automatic design would require either a dedicated Camera Extension or an explicit client-count IPC channel from the extension to the feeder.

---

# License

GPLv2. See [LICENSE](LICENSE).

This project includes and builds on work from PS3EYEDriver, libusb, and OBS virtual camera components.