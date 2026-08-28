// PS3EyeVCMenu.m — PS3 Eye virtual camera menu bar controller
// LaunchAgent stays resident; menu bar controls the physical camera state.
#import <Cocoa/Cocoa.h>

#define AGENT_LABEL @"com.bh2voq.ps3eye-vcam"
#define APP_AGENT_LABEL @"com.bh2voq.ps3eye-vcam-app"
#define FEED_NAME @"ps3eye-feed"
#define LANG_KEY @"PS3EyeLanguage"

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
    NSString *value = enabled ? @"1\n" : @"0\n";
    [value writeToFile:controlPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
@property NSMenu *menu;
@property NSMenuItem *statusMenuItem;
@property NSMenuItem *toggleItem;
@property NSMenuItem *logItem;
@property NSMenuItem *languageItem;
@property NSMenuItem *englishItem;
@property NSMenuItem *chineseItem;
@property NSMenuItem *quitItem;
@property NSTimer *timer;
@end

@implementation AppDelegate

- (BOOL)isChinese {
    NSString *lang = [[NSUserDefaults standardUserDefaults] stringForKey:LANG_KEY];
    return [lang isEqualToString:@"zh"];
}

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

- (void)applyLanguage {
    BOOL zh = [self isChinese];
    self.logItem.title = zh ? @"打开日志" : @"Open Log";
    self.languageItem.title = zh ? @"语言" : @"Language";
    self.englishItem.title = @"English";
    self.chineseItem.title = @"中文";
    self.englishItem.state = zh ? NSControlStateValueOff : NSControlStateValueOn;
    self.chineseItem.state = zh ? NSControlStateValueOn : NSControlStateValueOff;
    self.quitItem.title = zh ? @"退出菜单栏 App（后台保持待机）" : @"Quit Menu Bar App (Background Stays Idle)";
    [self refresh:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSArray<NSRunningApplication *> *instances = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.bh2voq.ps3eye-vcam"];
    if (instances.count > 1) { [NSApp terminate:nil]; return; }

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.menu = [[NSMenu alloc] init];

    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"PS3 Eye: ..." action:nil keyEquivalent:@""];
    self.statusMenuItem.enabled = NO;
    [self.menu addItem:self.statusMenuItem];

    self.toggleItem = [[NSMenuItem alloc] initWithTitle:@"Enable Camera" action:@selector(toggleCamera:) keyEquivalent:@""];
    self.toggleItem.target = self;
    [self.menu addItem:self.toggleItem];

    self.logItem = [[NSMenuItem alloc] initWithTitle:@"Open Log" action:@selector(openLog:) keyEquivalent:@""];
    self.logItem.target = self;
    [self.menu addItem:self.logItem];

    NSMenu *languageMenu = [[NSMenu alloc] init];
    self.englishItem = [[NSMenuItem alloc] initWithTitle:@"English" action:@selector(selectEnglish:) keyEquivalent:@""];
    self.englishItem.target = self;
    [languageMenu addItem:self.englishItem];
    self.chineseItem = [[NSMenuItem alloc] initWithTitle:@"中文" action:@selector(selectChinese:) keyEquivalent:@""];
    self.chineseItem.target = self;
    [languageMenu addItem:self.chineseItem];

    self.languageItem = [[NSMenuItem alloc] initWithTitle:@"Language" action:nil keyEquivalent:@""];
    self.languageItem.submenu = languageMenu;
    [self.menu addItem:self.languageItem];

    [self.menu addItem:[NSMenuItem separatorItem]];

    self.quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Menu Bar App (Background Stays Idle)" action:@selector(quitApp:) keyEquivalent:@"q"];
    self.quitItem.target = self;
    [self.menu addItem:self.quitItem];

    self.statusItem.menu = self.menu;

    if (ensureInstalled()) {
        startAgent();
        ensureAppAgent();
    }

    [self applyLanguage];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
}

- (void)refresh:(NSTimer *)t {
    (void)t;
    BOOL zh = [self isChinese];
    BOOL enabled = cameraEnabled();
    BOOL running = feedRunning();
    NSString *last = [self lastLogLine];
    NSString *state;

    if (!running) state = zh ? @"后台未运行" : @"Background Not Running";
    else if (!enabled) state = zh ? @"待机（摄像头已关闭）" : @"Standby (Camera Off)";
    else if ([last containsString:@"frames sent"] || [last containsString:@"streaming"]) state = zh ? @"推流中" : @"Streaming";
    else state = zh ? @"启动中…" : @"Starting...";

    self.toggleItem.title = enabled ? (zh ? @"关闭摄像头" : @"Disable Camera") : (zh ? @"启用摄像头" : @"Enable Camera");
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

- (void)selectEnglish:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setObject:@"en" forKey:LANG_KEY];
    [self applyLanguage];
}

- (void)selectChinese:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setObject:@"zh" forKey:LANG_KEY];
    [self applyLanguage];
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
