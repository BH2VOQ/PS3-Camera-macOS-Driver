// PS3EyeVCMenu.m — PS3 Eye 虚拟摄像头菜单栏控制 App
// LaunchAgent 常驻后台；菜单栏只控制物理 PS3 Eye 的手动启用/待机状态。
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
static NSString *controlPath(void) {
    return [supportDir() stringByAppendingPathComponent:@"enabled"];
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
    @try { [t launch]; [t waitUntilExit]; }
    @catch (NSException *e) { return -1; }
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

static BOOL cameraEnabled(void) {
    NSString *value = [NSString stringWithContentsOfFile:controlPath() encoding:NSUTF8StringEncoding error:nil];
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [value isEqualToString:@"1"];
}
static void setCameraEnabled(BOOL enabled) {
    [[NSFileManager defaultManager] createDirectoryAtPath:supportDir() withIntermediateDirectories:YES attributes:nil error:nil];
    [enabled ? @"1\n" : @"0\n" writeToFile:controlPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static BOOL ensureInstalled(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:supportDir() withIntermediateDirectories:YES attributes:nil error:nil];
    if (![fm fileExistsAtPath:controlPath()]) {
        [@"0\n" writeToFile:controlPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }

    NSString *bundled = [[NSBundle mainBundle] pathForResource:FEED_NAME ofType:nil];
    if (!bundled || ![fm fileExistsAtPath:bundled]) return NO;
    BOOL feedChanged = ![fm fileExistsAtPath:installedFeedPath()] || ![fm contentsEqualAtPath:bundled andPath:installedFeedPath()];

    NSString *plist = [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        @"<plist version=\"1.0\">\n<dict>\n"
        @"\t<key>Label</key><string>%@</string>\n"
        @"\t<key>ProgramArguments</key><array><string>%@</string></array>\n"
        @"\t<key>RunAtLoad</key><true/>\n"
        @"\t<key>KeepAlive</key><true/>\n"
        @"\t<key>ThrottleInterval</key><integer>2</integer>\n"
        @"\t<key>ProcessType</key><string>Background</string>\n"
        @"\t<key>StandardOutPath</key><string>%@</string>\n"
        @"\t<key>StandardErrorPath</key><string>%@</string>\n"
        @"</dict>\n</plist>\n", AGENT_LABEL, installedFeedPath(), logPath(), logPath()];

    NSString *existingPlist = [NSString stringWithContentsOfFile:agentPlistPath() encoding:NSUTF8StringEncoding error:nil];
    BOOL plistChanged = !(existingPlist && [existingPlist isEqualToString:plist]);
    if (feedChanged || plistChanged) unloadAgentIfLoaded();

    if (feedChanged) {
        [fm removeItemAtPath:installedFeedPath() error:nil];
        if (![fm copyItemAtPath:bundled toPath:installedFeedPath() error:nil]) return NO;
        [fm setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:installedFeedPath() error:nil];
    }
    if (plistChanged && ![plist writeToFile:agentPlistPath() atomically:YES encoding:NSUTF8StringEncoding error:nil]) return NO;
    return [fm fileExistsAtPath:installedFeedPath()];
}

static void startAgent(void) {
    if (feedRunning()) return;
    if (!agentLoaded()) {
        NSString *cmd = [NSString stringWithFormat:@"launchctl bootstrap gui/%@ %@ 2>&1; launchctl enable gui/%@/%@ 2>/dev/null; true",
                         uidString(), agentPlistPath(), uidString(), AGENT_LABEL];
        runShell(cmd);
    } else {
        NSString *cmd = [NSString stringWithFormat:@"launchctl kickstart -k gui/%@/%@ 2>/dev/null; true", uidString(), AGENT_LABEL];
        runShell(cmd);
    }
}

static BOOL appAgentLoaded(void) {
    NSString *cmd = [NSString stringWithFormat:@"launchctl print gui/%@/%@ >/dev/null 2>&1", uidString(), APP_AGENT_LABEL];
    return runShell(cmd) == 0;
}
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
            @"<plist version=\"1.0\"><dict>\n"
            @"<key>Label</key><string>%@</string>\n"
            @"<key>ProgramArguments</key><array><string>%@</string></array>\n"
            @"<key>RunAtLoad</key><true/>\n<key>ProcessType</key><string>Background</string>\n"
            @"</dict></plist>\n", APP_AGENT_LABEL, appBin];
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
@end

@implementation AppDelegate
- (NSString *)lastLogLine {
    NSString *log = [NSString stringWithContentsOfFile:logPath() encoding:NSUTF8StringEncoding error:nil];
    if (!log) return @"";
    NSArray<NSString *> *lines = [log componentsSeparatedByString:@"\n"];
    for (NSInteger i = lines.count - 1; i >= 0; i--) {
        NSString *l = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (l.length > 0) return l;
    }
    return @"";
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSArray<NSRunningApplication *> *instances = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.bh2voq.ps3eye-vcam"];
    if (instances.count > 1) { [NSApp terminate:nil]; return; }

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSMenu *menu = [[NSMenu alloc] init];
    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"PS3 Eye: …" action:nil keyEquivalent:@""];
    self.statusMenuItem.enabled = NO;
    [menu addItem:self.statusMenuItem];

    self.toggleItem = [[NSMenuItem alloc] initWithTitle:@"启用摄像头" action:@selector(toggleCamera:) keyEquivalent:@""];
    self.toggleItem.target = self;
    [menu addItem:self.toggleItem];

    NSMenuItem *logItem = [[NSMenuItem alloc] initWithTitle:@"打开日志" action:@selector(openLog:) keyEquivalent:@""];
    logItem.target = self;
    [menu addItem:logItem];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出菜单栏（后台保持待机）" action:@selector(quitApp:) keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];
    self.statusItem.menu = menu;

    if (ensureInstalled()) {
        startAgent();
        ensureAppAgent();
    }
    [self refresh:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
}

- (void)refresh:(NSTimer *)t {
    (void)t;
    BOOL enabled = cameraEnabled();
    BOOL running = feedRunning();
    NSString *last = [self lastLogLine];
    NSString *state;
    if (!running) state = @"后台未运行";
    else if (!enabled) state = @"待机（已关闭）";
    else if ([last containsString:@"frames sent"] || [last containsString:@"streaming"]) state = @"推流中";
    else state = @"启动中…";

    self.toggleItem.title = enabled ? @"关闭摄像头" : @"启用摄像头";
    self.statusMenuItem.title = [NSString stringWithFormat:@"PS3 Eye: %@", state];
    self.statusItem.button.title = enabled ? @"🎥●" : @"🎥○";
}

- (void)toggleCamera:(id)sender {
    (void)sender;
    BOOL enable = !cameraEnabled();
    setCameraEnabled(enable);
    if (!feedRunning()) startAgent();
    [self refresh:nil];
}

- (void)openLog:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:logPath()]];
}
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
