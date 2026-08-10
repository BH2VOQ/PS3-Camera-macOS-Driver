// consumer_watch.mm — 独立消费者检测进程：每秒检查 OBS Virtual Camera 是否被 App 使用，
// 结果写入 /tmp/ps3eye_consumer.txt（"1"=有消费者 "0"=无）。
// 与 feed 进程分离，避免 AVFoundation 枚举与 libusb 并发冲突（实测会崩）。
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

int main() {
    @autoreleasepool {
        while (1) {
            int inUse = 0;
            @autoreleasepool {
                NSArray<AVCaptureDevice *> *devs =
                    [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
                for (AVCaptureDevice *d in devs) {
                    if ([d.localizedName containsString:@"OBS Virtual Camera"]) {
                        inUse = (d.isInUseByAnotherApplication == YES) ? 1 : 0;
                        break;
                    }
                }
            }
            FILE *f = fopen("/tmp/ps3eye_consumer.txt", "w");
            if (f) { fprintf(f, "%d\n", inUse); fclose(f); }
            usleep(1000 * 1000); // 1 秒
        }
    }
    return 0;
}
