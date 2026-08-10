// PS3EyeVCMenu.m — PS3 Eye 虚拟摄像头菜单栏控制 App
// 双击启动 → 自动拉起 ps3eye-feed；菜单栏显示状态（待机/推流中/未运行）；
// 菜单可手动启停、打开日志；退出 App 时自动停止 feed。
#import <Cocoa/Cocoa.h>

static NSString *feedPath(void) {
    return [[NSBundle mainBundle] pathForResource:@"ps3eye-feed" ofType:nil];
}

static NSString *logPath(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/PS3Eye-VirtualCam"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"feed.log"];
}

static BOOL feedRunning(void) {
    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    t.arguments = @[@"-lc", @"pgrep -x ps3eye-feed >/dev/null 2>&1"];
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    t.standardError = p;
    @try {
        [t launch];
        [t waitUntilExit];
    } @catch (NSException *e) {
        return NO;
    }
    return t.terminationStatus == 0;
}

static void killFeed(void) {
    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    t.arguments = @[@"-lc", @"pkill -x ps3eye-feed 2>/dev/null; true"];
    @try {
        [t launch];
        [t waitUntilExit];
    } @catch (NSException *e) {}
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@property NSMenuItem *statusMenuItem;
@property NSMenuItem *toggleItem;
@property NSTimer *timer;
@property BOOL starting;
@end

@implementation AppDelegate

- (NSString *)lastLogLine {
    NSString *log = [NSString stringWithContentsOfFile:logPath() encoding:NSUTF8StringEncoding error:nil];
    if (!log) return @"(无日志)";
    NSArray<NSString *> *lines = [log componentsSeparatedByString:@"\n"];
    for (NSInteger i = lines.count - 1; i >= 0; i--) {
        NSString *l = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (l.length > 0) return l;
    }
    return @"(空日志)";
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSMenu *menu = [[NSMenu alloc] init];

    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"PS3 Eye: …" action:nil keyEquivalent:@""];
    self.statusMenuItem.enabled = NO;
    [menu addItem:self.statusMenuItem];

    self.toggleItem = [[NSMenuItem alloc] initWithTitle:@"启动" action:@selector(toggleFeed:) keyEquivalent:@""];
    self.toggleItem.target = self;
    [menu addItem:self.toggleItem];

    NSMenuItem *logItem = [[NSMenuItem alloc] initWithTitle:@"打开日志" action:@selector(openLog:) keyEquivalent:@""];
    logItem.target = self;
    [menu addItem:logItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出" action:@selector(quit:) keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
    [self refresh:nil];

    // 启动即自动拉起驱动（双击即用）
    if (!feedRunning()) [self startFeed];

    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
}

- (void)refresh:(NSTimer *)t {
    BOOL running = feedRunning();
    NSString *state;
    if (running) {
        NSString *last = [self lastLogLine];
        if ([last containsString:@"无消费者"]) state = @"待机中（LED 灭）";
        else if ([last containsString:@"检测到消费者"] || [last containsString:@"消费者仍在"] ||
                 [last containsString:@"frames sent"]) state = @"推流中（LED 亮）";
        else state = @"运行中";
        self.toggleItem.title = @"停止";
    } else {
        state = self.starting ? @"启动中…" : @"未运行";
        self.toggleItem.title = @"启动";
    }
    self.statusMenuItem.title = [NSString stringWithFormat:@"PS3 Eye: %@", state];
    self.statusItem.button.title = running ? @"🎥●" : @"🎥○";
}

- (void)startFeed {
    NSString *feed = feedPath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:feed]) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"未找到 ps3eye-feed";
        a.informativeText = @"App 包内缺少驱动可执行文件，请重新下载。";
        [a runModal];
        return;
    }
    self.starting = YES;
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath()];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:logPath() contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:logPath()];
    }
    [fh seekToEndOfFile];

    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:feed];
    t.standardOutput = fh;
    t.standardError = fh;
    __weak typeof(self) weakSelf = self;
    t.terminationHandler = ^(NSTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.starting = NO;
            [weakSelf refresh:nil];
        });
    };
    @try {
        [t launch];
    } @catch (NSException *e) {
        self.starting = NO;
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"启动失败";
        a.informativeText = e.reason;
        [a runModal];
    }
    [self refresh:nil];
}

- (void)toggleFeed:(id)sender {
    if (feedRunning()) {
        killFeed();
    } else {
        [self startFeed];
    }
    [self refresh:nil];
}

- (void)openLog:(id)sender {
    [[NSWorkspace sharedWorkspace] openFile:logPath()];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    // 兜底：任何退出路径（菜单/⌘Q/osascript/系统关机）都清理驱动进程
    killFeed();
}

- (void)quit:(id)sender {
    killFeed(); // 退出时清理驱动进程，避免孤儿
    [[NSApplication sharedApplication] terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
