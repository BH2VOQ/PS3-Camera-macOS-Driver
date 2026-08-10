// ps3eye-feed.mm — 极简 OBS 替代：PS3 Eye 抓帧 → 喂给 OBS Virtual Camera system extension
// 原理：OBS 的 macOS 虚拟摄像头（system extension）是常驻 daemon，
//       我们作为 CMIO 客户端往它的 Sink 流塞 sample buffer 即可。
// 前提：OBS 已安装且虚拟摄像头扩展已激活（装 OBS 后 Start Virtual Camera 一次）。

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMediaIO/CMIOHardware.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <signal.h>
#import <sys/file.h>
#import <fcntl.h>
#include <vector>
#include <cstdio>
#include <cstdlib>
#include "ps3eye.h"

static const NSUInteger kWidth  = 640;
static const NSUInteger kHeight = 480;
static const double     kSendFPS = 30.0; // 扩展的 source 描述 30fps，喂 30 最稳
static volatile sig_atomic_t g_running = 1;
static void on_signal(int sig) { g_running = 0; }

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

// ---- CMIO 工具 ----
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
        // 设备名（CFStringRef）
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
            // streams
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

            // ⚠️⚠️ 关键教训：direction 属性不可靠！实测（probe_streams）：
            // stream[0] direction=1 但 queue 永远满（扩展不消费）；stream[1] direction=0
            // 反而帧能被扩展消费（feed-nv12b 历史证据：index 1 帧持续增长、零 drop）。
            // OBS 官方源码取 index 1（NSMakeRange(sizeof(CMIOStreamID),...)）作为喂帧目标，
            // 必须照抄：优先 index 1，失败再试其他。direction 属性仅供参考。
            for (UInt32 ti = 0; ti < sCount; ti++) {
                UInt32 dir = 99;
                CMIOObjectPropertyAddress dirAddr = {kCMIOStreamPropertyDirection,
                                                     kCMIOObjectPropertyScopeGlobal,
                                                     kCMIOObjectPropertyElementMain};
                UInt32 dirSize = sizeof(dir);
                OSStatus drs = CMIOObjectGetPropertyData(streams[ti], &dirAddr, 0, NULL,
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
                    *outQueue = q;
                    fprintf(stderr, "  -> using stream[%u] as sink (OBS 官方 index 1)\n", si);
                    return true;
                }
            }
            fprintf(stderr, "  ERROR: no sink queue\n"); return false;
        }
    }
    return false;
}

// ---- 帧转换 BGR -> NV12（与 OBS 官方喂帧格式一致，BT.601 limited range）----
// OBS 官方实现：conversion.format = VIDEO_FORMAT_NV12 → kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
// 扩展 sink 期望 NV12；之前用 BGRA 导致 copyXPCDictionary 失败（Err -12704）→ 框架 use-after-free
static void bgr_to_nv12(const uint8_t *bgr, uint8_t *yPlane, uint8_t *uvPlane,
                        size_t w, size_t h) {
    const size_t yStride = w;
    const size_t uvStride = w;
    for (size_t y = 0; y < h; y += 2) {
        for (size_t x = 0; x < w; x += 2) {
            // 2x2 块取左上角像素做色度（NV12 色度采样）
            const uint8_t *p = bgr + (y * w + x) * 3;
            uint8_t B = p[0], G = p[1], R = p[2];
            // BT.601 limited range
            int Y = (66 * R + 129 * G + 25 * B + 128) >> 8;
            int Cb = (-38 * R - 74 * G + 112 * B + 128) >> 8;
            int Cr = (112 * R - 94 * G - 18 * B + 128) >> 8;
            Y  = Y  + 16;  if (Y  < 16) Y  = 16;  if (Y  > 235) Y  = 235;
            Cb = Cb + 128; if (Cb < 16) Cb = 16;  if (Cb > 240) Cb = 240;
            Cr = Cr + 128; if (Cr < 16) Cr = 16;  if (Cr > 240) Cr = 240;
            yPlane[y * yStride + x] = (uint8_t)Y;
            if (y + 1 < h) {
                const uint8_t *p2 = bgr + ((y + 1) * w + x) * 3;
                int Y2 = (66 * p2[2] + 129 * p2[1] + 25 * p2[0] + 128) >> 8;
                Y2 = Y2 + 16; if (Y2 < 16) Y2 = 16; if (Y2 > 235) Y2 = 235;
                yPlane[(y + 1) * yStride + x] = (uint8_t)Y2;
            }
            if (x + 1 < w) {
                const uint8_t *p3 = bgr + (y * w + x + 1) * 3;
                int Y3 = (66 * p3[2] + 129 * p3[1] + 25 * p3[0] + 128) >> 8;
                Y3 = Y3 + 16; if (Y3 < 16) Y3 = 16; if (Y3 > 235) Y3 = 235;
                yPlane[y * yStride + x + 1] = (uint8_t)Y3;
            }
            if (y + 1 < h && x + 1 < w) {
                const uint8_t *p4 = bgr + ((y + 1) * w + x + 1) * 3;
                int Y4 = (66 * p4[2] + 129 * p4[1] + 25 * p4[0] + 128) >> 8;
                Y4 = Y4 + 16; if (Y4 < 16) Y4 = 16; if (Y4 > 235) Y4 = 235;
                yPlane[(y + 1) * yStride + x + 1] = (uint8_t)Y4;
            }
            size_t uvIdx = (y / 2) * (uvStride) + x;
            uvPlane[uvIdx + 0] = (uint8_t)Cb;  // NV12: Cb 在前
            uvPlane[uvIdx + 1] = (uint8_t)Cr;
        }
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        fprintf(stderr, "[ps3eye-feed] starting\n");

        if (!acquireSingleInstanceLock()) return 1;
        signal(SIGINT, on_signal);
        signal(SIGTERM, on_signal);

        CMIOObjectID device = 0;
        CMIOStreamID sink = 0;
        CMSimpleQueueRef queue = NULL;
        if (!findSinkStream(&device, &sink, &queue)) {
            fprintf(stderr, "[ps3eye-feed] ERROR: OBS Virtual Camera not found/not activated. 请先安装 OBS 并 Start Virtual Camera 一次。\n");
            return 2;
        }

        OSStatus st = CMIODeviceStartStream(device, sink);
        if (st != noErr) {
            fprintf(stderr, "[ps3eye-feed] ERROR: CMIODeviceStartStream %d\n", st);
            return 3;
        }
        fprintf(stderr, "[ps3eye-feed] sink stream started\n");

        // ps3eye 初始化
        auto &devs = ps3eye::PS3EYECam::getDevices();
        if (devs.empty()) { fprintf(stderr, "[ps3eye-feed] ERROR: no PS3 Eye\n"); return 4; }
        auto cam = devs[0];
        if (!cam->init((uint32_t)kWidth, (uint32_t)kHeight, 60)) {
            fprintf(stderr, "[ps3eye-feed] ERROR: camera init failed\n"); return 5;
        }
        cam->start();
        fprintf(stderr, "[ps3eye-feed] PS3 Eye streaming (Ctrl+C 退出)\n");

        // NV12 像素缓冲池（与 OBS 官方一致：VIDEO_FORMAT_NV12 → 420YpCbCr8BiPlanarVideoRange）
        // 关键：必须 IOSurface-backed，CMIOExtension 跨进程传帧走 XPC 序列化，
        // 普通内存 buffer 会 copyXPCDictionary 失败（Err -12704）→ 框架内部 use-after-free 崩溃
        NSDictionary *pbAttr = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            (id)kCVPixelBufferWidthKey: @(kWidth),
            (id)kCVPixelBufferHeightKey: @(kHeight),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        };
        CVPixelBufferPoolRef pool = NULL;
        CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)pbAttr, &pool);
        if (!pool) { fprintf(stderr, "[ps3eye-feed] ERROR: pixel buffer pool\n"); return 6; }

        // NV12 格式描述（与 pool 一致）
        CMVideoFormatDescriptionRef fmt = NULL;
        CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                       kWidth, kHeight, NULL, &fmt);

        std::vector<uint8_t> bgr(kWidth * kHeight * 3);

        CMTime duration = CMTimeMake(1, (int32_t)kSendFPS);
        CMTime pts = kCMTimeInvalid;
        int64_t lastSendNs = 0;
        uint64_t frameCount = 0;

        // 无消费者自动停摄像头（用户需求）：用 AVFoundation isInUseByAnotherApplication 检测。
        // ⚠️ 不用 kCMIODevicePropertyDeviceIsRunning：feed 自己启动了 sink 流，该属性恒=1（实测）。
        // AVFoundation 查询：Photo Booth 等 App 打开 OBS Virtual Camera 时 isInUse 变 1；
        // feed 用 CMIO 不算 AVFoundation 使用者（实测恒 0），所以这是可靠的「真消费者」信号。
        bool camRunning = true;
        // ⚠️ 必须初始化为当前时间！若为 0，第一次循环 nowNs-0 >= 1s 立即成立，
        // 启动瞬间就 cam->stop() → 与刚起步的 USB 传输线程竞态 → libusb 互斥锁断言崩溃
        int64_t lastCheckNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        const int64_t kCheckInterval = NSEC_PER_SEC; // 每秒检查一次

        // 消费者检测：读独立进程 consumer_watch 写入的结果文件（/tmp/ps3eye_consumer.txt）。
        // ⚠️ 不能在 feed 进程内直接调 AVFoundation（devicesWithMediaType 枚举会与 libusb
        // 并发冲突导致 pthread_mutex_lock 断言崩溃，实测验证过）。独立进程方案已验证安全。
        auto checkConsumer = [&]() -> bool {
            FILE *f = fopen("/tmp/ps3eye_consumer.txt", "r");
            if (!f) return false; // 文件不存在视为无消费者
            int v = 0;
            if (fscanf(f, "%d", &v) != 1) v = 0;
            fclose(f);
            return v != 0;
        };

        while (g_running) {
            // 周期性消费者检测（每秒一次）
            int64_t nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            if (nowNs - lastCheckNs >= kCheckInterval) {
                lastCheckNs = nowNs;
                bool consumerActive = checkConsumer();
                if (!consumerActive && camRunning) {
                    cam->stop();
                    camRunning = false;
                    fprintf(stderr, "[ps3eye-feed] 无消费者，摄像头已停止 (省电)\n");
                } else if (consumerActive && !camRunning) {
                    cam->start();
                    camRunning = true;
                    fprintf(stderr, "[ps3eye-feed] 检测到消费者，摄像头已恢复\n");
                }
            }

            if (!camRunning) {
                // 省电模式：不抓帧不喂帧，独立等待循环（每秒检查消费者是否回来）
                usleep(200 * 1000);
                continue;
            }

            cam->getFrame(bgr.data()); // blocks until new frame (~60fps)

            nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            if (nowNs - lastSendNs < (int64_t)(NSEC_PER_SEC / kSendFPS)) continue;
            lastSendNs = nowNs;

            // 满队列则丢帧（sink buffer queue size = 1）
            double fullness = CMSimpleQueueGetFullness(queue);
            if (fullness >= 1.0) continue;

            CVPixelBufferRef pb = NULL;
            CVReturn cv = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb);
            if (cv != kCVReturnSuccess) continue;
            CVPixelBufferLockBaseAddress(pb, 0);
            uint8_t *yPlane  = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pb, 0);
            uint8_t *uvPlane = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pb, 1);
            bgr_to_nv12(bgr.data(), yPlane, uvPlane, kWidth, kHeight);
            CVPixelBufferUnlockBaseAddress(pb, 0);

            if (CMTIME_IS_INVALID(pts))
                pts = CMTimeMake(nowNs, NSEC_PER_SEC);
            CMSampleTimingInfo timing = {duration, pts, kCMTimeInvalid};
            CMSampleBufferRef sb = NULL;
            OSStatus ss = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pb, true, NULL, NULL,
                                                             fmt, &timing, &sb);
            CVPixelBufferRelease(pb);
            if (ss == noErr && sb) {
                CMSimpleQueueEnqueue(queue, sb);
                // ⚠️ 不 CFRelease(sb)！与 OBS 官方实现一致：
                // CMSimpleQueueEnqueue 时队列 retain 一次，框架消费出队时 release 一次，
                // 我们若再 CFRelease 会多减引用计数 → 框架异步消费时 use-after-free（objc_retain 悬垂崩溃）
                frameCount++;
                if (frameCount % 30 == 0)
                    fprintf(stderr, "[ps3eye-feed] %llu frames sent\n", (unsigned long long)frameCount);
            }
            pts = CMTimeAdd(pts, duration);
        }

        // 优雅退出
        fprintf(stderr, "[ps3eye-feed] stopping...\n");
        CMIODeviceStopStream(device, sink);
        cam->stop();
        if (pool) CVPixelBufferPoolRelease(pool);
        if (fmt) CFRelease(fmt);
        fprintf(stderr, "[ps3eye-feed] cleaned up, bye\n");
    }
    return 0;
}
