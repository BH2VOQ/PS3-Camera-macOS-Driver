// ps3eye-feed.mm — PS3 Eye 抓帧 → OBS Virtual Camera sink
// 设计目标：待机时物理相机关闭；CMIO 检测到真实 source 客户端后启动，并在本次会话内保持稳定。
// 注意：OBS Camera Extension 不向外部 feeder 暴露可靠的 source-client 关闭计数，
// 因此绝不能用 AVFoundation inUseByAnotherApplication=false 作为关机依据，否则 QuickTime 会被周期性误杀。

#import <Foundation/Foundation.h>
#import <CoreMediaIO/CMIOHardware.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <signal.h>
#import <sys/file.h>
#import <fcntl.h>
#include <vector>
#include <cstdio>
#include <cstdlib>
#include <atomic>
#include <thread>
#include "ps3eye.h"

static const NSUInteger kWidth  = 640;
static const NSUInteger kHeight = 480;
static const double     kSendFPS = 30.0;
static volatile sig_atomic_t g_running = 1;
static void on_signal(int sig) { (void)sig; g_running = 0; }

static bool acquireSingleInstanceLock() {
    static int lockfd = -1;
    lockfd = open("/tmp/ps3eye-feed.lock", O_CREAT | O_RDWR, 0644);
    if (lockfd < 0) return false;
    if (flock(lockfd, LOCK_EX | LOCK_NB) != 0) {
        fprintf(stderr, "[ps3eye-feed] 另一个实例已在运行（/tmp/ps3eye-feed.lock）\n");
        return false;
    }
    return true;
}

static OSStatus getCMIOProperty(CMIOObjectID obj, CMIOObjectPropertySelector sel,
                                CMIOObjectPropertyScope scope, CMIOObjectPropertyElement element,
                                void *data, UInt32 *dataSize) {
    CMIOObjectPropertyAddress addr = {sel, scope, element};
    return CMIOObjectGetPropertyData(obj, &addr, 0, NULL, *dataSize, dataSize, data);
}

static UInt32 getCMIOPropertyDataSize(CMIOObjectID obj, CMIOObjectPropertySelector sel,
                                      CMIOObjectPropertyScope scope, CMIOObjectPropertyElement element) {
    CMIOObjectPropertyAddress addr = {sel, scope, element};
    UInt32 size = 0;
    CMIOObjectGetPropertyDataSize(obj, &addr, 0, NULL, &size);
    return size;
}

static bool isCMIODeviceRunningSomewhere(CMIOObjectID device) {
    UInt32 running = 0;
    UInt32 size = sizeof(running);
    OSStatus status = getCMIOProperty(device,
                                      kCMIODevicePropertyDeviceIsRunningSomewhere,
                                      kCMIOObjectPropertyScopeGlobal,
                                      kCMIOObjectPropertyElementMain,
                                      &running, &size);
    return status == noErr && running != 0;
}

static bool findSinkStream(CMIOObjectID *outDevice, CMIOStreamID *outSinkStream,
                           CMSimpleQueueRef *outQueue) {
    UInt32 size = getCMIOPropertyDataSize(kCMIOObjectSystemObject, kCMIOHardwarePropertyDevices,
                                          kCMIOObjectPropertyScopeGlobal, kCMIOObjectPropertyElementMain);
    if (size == 0) { fprintf(stderr, "no CMIO devices\n"); return false; }
    NSMutableData *devData = [NSMutableData dataWithLength:size];
    CMIOObjectPropertyAddress devAddr = {kCMIOHardwarePropertyDevices,
                                         kCMIOObjectPropertyScopeGlobal,
                                         kCMIOObjectPropertyElementMain};
    CMIOObjectGetPropertyData(kCMIOObjectSystemObject, &devAddr, 0, NULL, size, &size, [devData mutableBytes]);
    CMIOObjectID *devices = (CMIOObjectID *)[devData mutableBytes];
    UInt32 count = size / sizeof(CMIOObjectID);

    for (UInt32 i = 0; i < count; i++) {
        UInt32 nameSize = getCMIOPropertyDataSize(devices[i], kCMIOObjectPropertyName,
                                                  kCMIOObjectPropertyScopeGlobal,
                                                  kCMIOObjectPropertyElementMain);
        NSString *name = nil;
        if (nameSize > 0) {
            NSMutableData *nameData = [NSMutableData dataWithLength:nameSize];
            OSStatus rs = getCMIOProperty(devices[i], kCMIOObjectPropertyName,
                                          kCMIOObjectPropertyScopeGlobal, kCMIOObjectPropertyElementMain,
                                          [nameData mutableBytes], &nameSize);
            if (rs == noErr && nameSize >= sizeof(CFStringRef)) {
                CFStringRef nameRef = *(CFStringRef *)[nameData mutableBytes];
                name = (__bridge NSString *)nameRef;
            }
        }
        fprintf(stderr, "  device: %s\n", name ? name.UTF8String : "(unknown)");

        if ([name containsString:@"OBS Virtual Camera"]) {
            UInt32 sSize = getCMIOPropertyDataSize(devices[i], kCMIODevicePropertyStreams,
                                                   kCMIOObjectPropertyScopeGlobal,
                                                   kCMIOObjectPropertyElementMain);
            NSMutableData *sData = [NSMutableData dataWithLength:sSize];
            getCMIOProperty(devices[i], kCMIODevicePropertyStreams,
                            kCMIOObjectPropertyScopeGlobal, kCMIOObjectPropertyElementMain,
                            [sData mutableBytes], &sSize);
            CMIOStreamID *streams = (CMIOStreamID *)[sData mutableBytes];
            UInt32 sCount = sSize / sizeof(CMIOStreamID);
            fprintf(stderr, "  streams: %u\n", sCount);

            for (UInt32 ti = 0; ti < sCount; ti++) {
                UInt32 dir = 99;
                CMIOObjectPropertyAddress dirAddr = {kCMIOStreamPropertyDirection,
                                                     kCMIOObjectPropertyScopeGlobal,
                                                     kCMIOObjectPropertyElementMain};
                UInt32 dirSize = sizeof(dir);
                CMIOObjectGetPropertyData(streams[ti], &dirAddr, 0, NULL,
                                          dirSize, &dirSize, &dir);
                fprintf(stderr, "    stream[%u] id=%u direction=%u (%s)\n", ti, streams[ti], dir,
                        dir == 0 ? "OUT/source" : (dir == 1 ? "IN/sink" : "?"));
            }

            UInt32 tryOrder[2] = {1, 0};
            UInt32 tryCount = sCount >= 2 ? 2 : sCount;
            for (UInt32 ti = 0; ti < tryCount; ti++) {
                UInt32 si = tryOrder[ti];
                CMSimpleQueueRef q = NULL;
                OSStatus qs = CMIOStreamCopyBufferQueue(streams[si],
                                                        [](CMIOStreamID, void *, void *) {},
                                                        NULL, &q);
                fprintf(stderr, "    stream[%u] id=%u CopyBufferQueue=%d queue=%p\n", si, streams[si], qs, q);
                if (qs == noErr && q) {
                    *outDevice = devices[i];
                    *outSinkStream = streams[si];
                    if (outQueue) *outQueue = q;
                    else CFRelease(q);
                    fprintf(stderr, "  -> using stream[%u] as sink (OBS 官方 index 1)\n", si);
                    return true;
                }
            }
            fprintf(stderr, "  ERROR: no sink queue\n");
            return false;
        }
    }
    return false;
}

static void bgr_to_nv12(const uint8_t *bgr, uint8_t *yPlane, uint8_t *uvPlane,
                        size_t w, size_t h) {
    const size_t yStride = w;
    const size_t uvStride = w;
    for (size_t y = 0; y < h; y += 2) {
        for (size_t x = 0; x < w; x += 2) {
            const uint8_t *p = bgr + (y * w + x) * 3;
            uint8_t B = p[0], G = p[1], R = p[2];
            int Y = (66 * R + 129 * G + 25 * B + 128) >> 8;
            int Cb = (-38 * R - 74 * G + 112 * B + 128) >> 8;
            int Cr = (112 * R - 94 * G - 18 * B + 128) >> 8;
            Y  += 16;  if (Y < 16) Y = 16; if (Y > 235) Y = 235;
            Cb += 128; if (Cb < 16) Cb = 16; if (Cb > 240) Cb = 240;
            Cr += 128; if (Cr < 16) Cr = 16; if (Cr > 240) Cr = 240;
            yPlane[y * yStride + x] = (uint8_t)Y;
            if (y + 1 < h) {
                const uint8_t *p2 = bgr + ((y + 1) * w + x) * 3;
                int Y2 = ((66 * p2[2] + 129 * p2[1] + 25 * p2[0] + 128) >> 8) + 16;
                if (Y2 < 16) Y2 = 16; if (Y2 > 235) Y2 = 235;
                yPlane[(y + 1) * yStride + x] = (uint8_t)Y2;
            }
            if (x + 1 < w) {
                const uint8_t *p3 = bgr + (y * w + x + 1) * 3;
                int Y3 = ((66 * p3[2] + 129 * p3[1] + 25 * p3[0] + 128) >> 8) + 16;
                if (Y3 < 16) Y3 = 16; if (Y3 > 235) Y3 = 235;
                yPlane[y * yStride + x + 1] = (uint8_t)Y3;
            }
            if (y + 1 < h && x + 1 < w) {
                const uint8_t *p4 = bgr + ((y + 1) * w + x + 1) * 3;
                int Y4 = ((66 * p4[2] + 129 * p4[1] + 25 * p4[0] + 128) >> 8) + 16;
                if (Y4 < 16) Y4 = 16; if (Y4 > 235) Y4 = 235;
                yPlane[(y + 1) * yStride + x + 1] = (uint8_t)Y4;
            }
            size_t uvIdx = (y / 2) * uvStride + x;
            uvPlane[uvIdx] = (uint8_t)Cb;
            uvPlane[uvIdx + 1] = (uint8_t)Cr;
        }
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        (void)argc; (void)argv;
        fprintf(stderr, "[ps3eye-feed] starting\n");
        if (!acquireSingleInstanceLock()) return 1;
        signal(SIGINT, on_signal);
        signal(SIGTERM, on_signal);

        CMIOObjectID device = 0;
        CMIOStreamID sink = 0;
        CMSimpleQueueRef queue = NULL;
        if (!findSinkStream(&device, &sink, NULL)) {
            fprintf(stderr, "[ps3eye-feed] ERROR: OBS Virtual Camera not found/not activated. 请先安装 OBS 并 Start Virtual Camera 一次。\n");
            return 2;
        }

        auto &devs = ps3eye::PS3EYECam::getDevices();
        if (devs.empty()) { fprintf(stderr, "[ps3eye-feed] ERROR: no PS3 Eye\n"); return 4; }
        auto cam = devs[0];
        if (!cam->init((uint32_t)kWidth, (uint32_t)kHeight, 30)) {
            fprintf(stderr, "[ps3eye-feed] ERROR: camera init failed\n");
            return 5;
        }
        cam->setAutogain(true);
        cam->setAutoWhiteBalance(true);
        cam->setBrightness(24);
        cam->setLed(false);
        fprintf(stderr, "[ps3eye-feed] PS3 Eye idle (sensor not streaming); waiting for CMIO consumer\n");

        // feeder 自己此时没有 StartStream，因此 DeviceIsRunningSomewhere=true 可作为 source 客户端唤醒信号。
        while (g_running && !isCMIODeviceRunningSomewhere(device)) {
            usleep(100 * 1000);
        }
        if (!g_running) std::_Exit(0);
        fprintf(stderr, "[ps3eye-feed] CMIO consumer detected; starting sink + physical camera\n");

        OSStatus qs = CMIOStreamCopyBufferQueue(sink,
                                                [](CMIOStreamID, void *, void *) {},
                                                NULL, &queue);
        if (qs != noErr || !queue) {
            fprintf(stderr, "[ps3eye-feed] ERROR: CopyBufferQueue failed %d\n", qs);
            return 7;
        }
        OSStatus st = CMIODeviceStartStream(device, sink);
        if (st != noErr) {
            fprintf(stderr, "[ps3eye-feed] ERROR: StartStream failed %d\n", st);
            CFRelease(queue);
            return 8;
        }
        fprintf(stderr, "[ps3eye-feed] sink stream started\n");

        NSDictionary *pbAttr = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            (id)kCVPixelBufferWidthKey: @(kWidth),
            (id)kCVPixelBufferHeightKey: @(kHeight),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        };
        CVPixelBufferPoolRef pool = NULL;
        CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)pbAttr, &pool);
        if (!pool) return 6;
        CMVideoFormatDescriptionRef fmt = NULL;
        CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                       kWidth, kHeight, NULL, &fmt);
        CMTime duration = CMTimeMake(1, (int32_t)kSendFPS);

        auto enqueueFrame = [&](const uint8_t *bgr) -> bool {
            if (!queue || CMSimpleQueueGetFullness(queue) >= 1.0) return false;
            CVPixelBufferRef pb = NULL;
            if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) != kCVReturnSuccess || !pb) return false;
            CVPixelBufferLockBaseAddress(pb, 0);
            bgr_to_nv12(bgr,
                        (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pb, 0),
                        (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pb, 1),
                        kWidth, kHeight);
            CVPixelBufferUnlockBaseAddress(pb, 0);
            int64_t nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            CMSampleTimingInfo timing = {duration, CMTimeMake(nowNs, NSEC_PER_SEC), kCMTimeInvalid};
            CMSampleBufferRef sb = NULL;
            OSStatus ss = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pb, true, NULL, NULL,
                                                             fmt, &timing, &sb);
            CVPixelBufferRelease(pb);
            if (ss != noErr || !sb) return false;
            CMSimpleQueueEnqueue(queue, sb);
            return true;
        };

        cam->start();
        cam->setLed(true);
        fprintf(stderr, "[ps3eye-feed] PS3 Eye streaming 640x480@30 (stable session; false auto-idle disabled)\n");

        std::vector<uint8_t> bgr(kWidth * kHeight * 3);
        uint64_t frameCount = 0;
        int64_t startedNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        std::atomic<int64_t> lastFrameNs(startedNs);
        std::atomic<bool> captureActive(true);

        std::thread watchdog([&lastFrameNs, &captureActive]() {
            const int64_t kStallNs = 3 * NSEC_PER_SEC;
            while (g_running) {
                usleep(500 * 1000);
                if (!captureActive.load(std::memory_order_relaxed)) continue;
                int64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
                if (now - lastFrameNs.load(std::memory_order_relaxed) > kStallNs) {
                    fprintf(stderr, "[ps3eye-feed] FATAL: no camera frame for 3s; exiting for LaunchAgent recovery\n");
                    fflush(stderr);
                    std::_Exit(20);
                }
            }
        });

        // OBS Camera Extension 的 sink 启动后，DeviceIsRunningSomewhere 会包含 feeder 自己；
        // AVCaptureDevice.inUseByAnotherApplication 对 QuickTime + 虚拟设备又会误报 false。
        // 因此在没有 extension 端 client-count 通道之前，本次活跃会话只允许显式停止/进程重启，
        // 绝不再根据不可靠信号自动 _Exit()，避免每约 10 秒断流一次。
        while (g_running) {
            cam->getFrame(bgr.data());
            int64_t nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            lastFrameNs.store(nowNs, std::memory_order_relaxed);

            if (queue && CMSimpleQueueGetFullness(queue) < 1.0 && enqueueFrame(bgr.data())) {
                frameCount++;
                if (frameCount % 30 == 0)
                    fprintf(stderr, "[ps3eye-feed] %llu frames sent\n", (unsigned long long)frameCount);
            }
        }

        captureActive.store(false, std::memory_order_relaxed);
        if (watchdog.joinable()) watchdog.join();
        fprintf(stderr, "[ps3eye-feed] stopping...\n");
        CMIODeviceStopStream(device, sink);
        if (queue) CFRelease(queue);
        cam->setLed(false);
        if (pool) CVPixelBufferPoolRelease(pool);
        if (fmt) CFRelease(fmt);
        fflush(stderr);
        std::_Exit(0);
    }
}
