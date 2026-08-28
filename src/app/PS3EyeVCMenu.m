// PS3EyeVCMenu.m — PS3 Eye 虚拟摄像头菜单栏控制 App
// 架构：驱动通过 LaunchAgent（com.bh2voq.ps3eye-vcam）常驻后台——
// 开机自启、崩溃自动拉起、退出 App 不影响驱动。App 只负责：
//   首次启动/升级时安装最新 feeder + 注册 LaunchAgent
//   菜单栏状态显示、手动启停、打开日志
#import <Cocoa/Cocoa.h>

#define AGENT_LABEL @"com.bh2voq.ps3eye-vcam"
#define APP_AGENT_LABEL @"com.bh2voq.ps3eye-vcam-app"
#define FEED_NAME  @"ps3eye-feed"

static NSString *appAgentPlistPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.bh2voq.ps3eye-vcam-app.plist"];
}

static NSString *supportDir(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/PS3Eye-VirtualCam"];
}
static NSString *installedFeedPath(void) {
    return [supportDir() stringByAppendingPathComponent:FEED_NAME];
}
static NSString *agentPlistPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.bh2voq.ps3eye-vcam.plist"];
}
static NSString *logPath(void) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/PS3Eye-VirtualCam"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"feed.log"];
}

static int runShell(NSString *cmd) {
    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    t.arguments = @[@"-lc", cmd];
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    t.standardError = p;
    @try {
        [t launch];
        [t waitUntilExit];
    } @catch (NSException *e) {
        return -1;
    }
    return t.terminationStatus;
}

static NSString *uidString(void) {
    return [NSString stringWithFormat:@"%d", (int)getuid()];
}

static BOOL feedRunning(void) {
    return runShell(@"pgrep -x ps3eye-feed >/dev/null 2>&1") == 0;
}

static BOOL agentLoaded(void) {
    NSString *cmd = [NSString stringWithFormat:@"launchctl print gui/%@/%@ >/dev/null 2>&1", uidString(), AGENT_LABEL];
    return runShell(cmd) == 0;
}

static void unloadAgentIfLoaded(void) {
    if (!agentLoaded()) return;
    NSString *cmd = [NSString stringWithFormat:@"launchctl bootout gui/%@/%@ 2>/dev/null; true", uidString(), AGENT_LABEL];
    runShell(cmd);
}

// 安装/升级：保证 Application Support 中永远是 App 当前捆绑的 feeder，
// 同时刷新 LaunchAgent。旧版只在文件不存在时复制，导致升级后仍长期运行旧二进制。
static BOOL ensureInstalled(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:supportDir() withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *bundled = [[NSBundle mainBundle] pathForResource:FEED_NAME ofType:nil];
    if (!bundled || ![fm fileExistsAtPath:bundled]) return NO;

    BOOL feedChanged = ![fm fileExistsAtPath:installedFeedPath()] ||
                       ![fm contentsEqualAtPath:bundled andPath:installedFeedPath()];

    NSString *plist = [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n"
        @"<dict>\n"
        @"\t<key>Label</key><string>%@</string>\n"
        @"\t<key>ProgramArguments</key>\n"
        @"\t<array><string>%@</string></array>\n"
        @"\t<key>RunAtLoad</key><true/>\n"
        @"\t<key>KeepAlive</key><true/>\n"
        @"\t<key>ThrottleInterval</key><integer>2</integer>\n"
        @"\t<key>ProcessType</key><string>Background</string>\n"
        @"\t<key>StandardOutPath</key><string>%@</string>\n"
        @"\t<key>StandardErrorPath</key><string>%@</string>\n"
        @"</dict>\n"
        @"</plist>\n", AGENT_LABEL, installedFeedPath(), logPath(), logPath()];

    NSString *existingPlist = [NSString stringWithContentsOfFile:agentPlistPath()
                                                         encoding:NSUTF8StringEncoding
                                                            error:nil];
    BOOL plistChanged = !(existingPlist && [existingPlist isEqualToString:plist]);

    // 若 feeder 或 plist 有变化，先卸载旧 job，确保随后 bootstrap 的一定是新二进制/新参数。
    if (feedChanged || plistChanged) unloadAgentIfLoaded();

    if (feedChanged) {
        [fm removeItemAtPath:installedFeedPath() error:nil];
        NSError *copyError = nil;
        if (![fm copyItemAtPath:bundled toPath:installedFeedPath() error:&copyError]) {
            NSLog(@"Failed to update feeder: %@", copyError);
            return NO;
        }
        [fm setAttributes:@{NSFilePosixPermissions: @0755}
             ofItemAtPath:installedFeedPath()
                    error:nil];
    }

    if (plistChanged) {
        if (![plist writeToFile:agentPlistPath() atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
            return NO;
        }
    }

    return [fm fileExistsAtPath:installedFeedPath()];
}

static void startAgent(void) {
    if (feedRunning()) return;
    if (!agentLoaded()) {
        NSString *cmd = [NSString stringWithFormat:@"launchctl bootstrap gui/%@ %@ 2>&1; "
                         @"launchctl enable gui/%@/%@ 2>/dev/null; true", uidString(), agentPlistPath(), uidString(), AGENT_LABEL];
        runShell(cmd);
    } else {
        NSString *cmd = [NSString stringWithFormat:@"launchctl kickstart -k gui/%@/%@ 2>/dev/null; true", uidString(), AGENT_LABEL];
        runShell(cmd);
    }
}

static void stopAgent(void) {
    NSString *cmd = [NSString stringWithFormat:@"launchctl bootout gui/%@/%@ 2>/dev/null; "
                     @"pkill -x %@ 2>/dev/null; true", uidString(), AGENT_LABEL, FEED_NAME];
    runShell(cmd);
}

static BOOL appAgentLoaded(void) {
    NSString *cmd = [NSString stringWithFormat:@"launchctl print gui/%@/%@ >/dev/null 2>&1", uidString(), APP_AGENT_LABEL];
    return runShell(cmd) == 0;
}

// 注册 App 自身开机自启（菜单栏图标登录即有）；App 路径变化时更新 plist
static void ensureAppAgent(void) {
    NSString *appBin = [[NSBundle mainBundle] executablePath];
    if (!appBin) return;
    NSString *plistPath = appAgentPlistPath();
    NSString *existing = [NSString stringWithContentsOfFile:plistPath encoding:NSUTF8StringEncoding error:nil];
    BOOL needsWrite = !(existing && [existing containsString:appBin]);
    if (needsWrite) {
        if (appAgentLoaded()) {
            NSString *un = [NSString stringWithFormat:@"launchctl bootout gui/%@/%@ 2>/dev/null; true", uidString(), APP_AGENT_LABEL];
            runShell(un);
        }
        NSString *plist = [NSString stringWithFormat:
            @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
            @"<plist version=\"1.0\">\n"
            @"<dict>\n"
            @"\t<key>Label</key><string>%@</string>\n"
            @"\t<key>ProgramArguments</key>\n"
            @"\t<array><string>%@</string></array>\n"
            @"\t<key>RunAtLoad</key><true/>\n"
            @"\t<key>ProcessType</key><string>Background</string>\n"
            @"</dict>\n"
            @"</plist>\n", APP_AGENT_LABEL, appBin];
        [plist writeToFile:plistPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    if (!appAgentLoaded()) {
        NSString *cmd = [NSString stringWithFormat:@"launchctl bootstrap gui/%@ %@ 2>&1; true", uidString(), plistPath];
        runShell(cmd);
    }
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
    (void)notification;
    NSArray<NSRunningApplication *> *instances =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.bh2voq.ps3eye-vcam"];
    if (instances.count > 1) {
        [NSApp terminate:nil];
        return;
    }

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

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出（驱动保持后台常驻）" action:@selector(quitApp:) keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
    [self refresh:nil];

    if (ensureInstalled()) {
        startAgent();
        ensureAppAgent();
    } else {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText = @"安装失败";
        a.informativeText = @"无法安装或更新驱动文件，请重新下载 App。";
        [a runModal];
    }

    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
}

- (void)refresh:(NSTimer *)t {
    (void)t;
    BOOL running = feedRunning();
    NSString *state;
    if (running) {
        NSString *last = [self lastLogLine];
        if ([last containsString:@"frames sent"]) state = @"推流中";
        else if ([last containsString:@"FATAL"]) state = @"正在自动恢复";
        else state = @"运行中（待命）";
        self.toggleItem.title = @"停止";
    } else {
        state = self.starting ? @"启动中…" : @"未运行";
        self.toggleItem.title = @"启动";
    }
    self.statusMenuItem.title = [NSString stringWithFormat:@"PS3 Eye: %@", state];
    self.statusItem.button.title = running ? @"🎥●" : @"🎥○";
}

- (void)toggleFeed:(id)sender {
    (void)sender;
    if (feedRunning()) {
        stopAgent();
    } else {
        startAgent();
    }
    [self refresh:nil];
}

- (void)openLog:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:logPath()]];
}

// 退出只退出 App，驱动由 LaunchAgent 继续常驻
- (void)quitApp:(id)sender {
    (void)sender;
    [[NSApplication sharedApplication] terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        (void)argc; (void)argv;
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
