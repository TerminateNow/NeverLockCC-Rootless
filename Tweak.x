// NeverLockCC — SpringBoard side.
//
// SpringBoard builds an SBIdleTimerDescriptor (how long until dim/lock) for the
// current context: lock screen, home screen, app, etc. We hook the factory that
// builds it. When the tweak should be active we either hand back SpringBoard's
// own "disabled" descriptor (screen never times out) or a copy stretched to
// the user's custom timeout.

#import <UIKit/UIKit.h>
#import "Shared/NLCPrefs.h"

@interface SBIdleTimerDescriptor : NSObject <NSCopying>
@property (nonatomic) double totalInterval;
@property (nonatomic) double warnInterval;
@property (nonatomic) double quickUnwarnInterval;
@property (nonatomic) long long timerMode;
@end

@interface SBIdleTimerDescriptorFactory : NSObject
+ (SBIdleTimerDescriptor *)disabledIdleTimerDescriptor;
@end

@interface SBIdleTimerGlobalCoordinator : NSObject
+ (instancetype)sharedInstanceIfExists;
- (void)_idleTimerPrefsChanged;
- (BOOL)_updateIdleTimerForReason:(NSString *)reason;
- (void)resetIdleTimerForReason:(NSString *)reason;
@end

static BOOL gEnabled = YES;
static BOOL gAlwaysOn = NO;
static BOOL gTimerEnabled = NO;
static NSTimeInterval gTimerSeconds = kNLCDefaultTimerSeconds;
static BOOL gLastActive = NO;
// Set if SpringBoard ever rejects our custom timer, so we stop producing it
// instead of crash-looping SpringBoard.
static BOOL gCustomTimerFailed = NO;
static BOOL gSafetyNetInstalled = NO;
static void NLCInstallSafetyNet(void);

// Debug log for timer mode: /var/mobile/Library/Logs/NeverLockCC.log
// (read it with `cat` over SSH). Kept under ~64 KB.
static void NLCLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[NeverLockCC] %@", message);

    static NSString *path = @"/var/mobile/Library/Logs/NeverLockCC.log";
    static NSDateFormatter *formatter;
    if (!formatter) {
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"HH:mm:ss";
    }
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], message];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([[fm attributesOfItemAtPath:path error:nil] fileSize] > 64 * 1024) [fm removeItemAtPath:path error:nil];
    if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

static BOOL NLCIsOnPower(void) {
    // "Full" counts too: the phone is still on the charger, and the screen
    // should not suddenly start locking once the battery tops off.
    UIDeviceBatteryState state = [UIDevice currentDevice].batteryState;
    return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
}

static BOOL NLCShouldBeActive(void) {
    return gEnabled && (gAlwaysOn || NLCIsOnPower());
}

static void NLCLoadPrefs(void) {
    gEnabled = NLCGetBool(kNLCKeyEnabled, YES);
    gAlwaysOn = NLCGetBool(kNLCKeyAlwaysOn, NO);
    gTimerEnabled = NLCGetBool(kNLCKeyTimerEnabled, NO);
    gTimerSeconds = NLCGetTimerSeconds();
}

// Ask SpringBoard to rebuild its idle timer so the hook below is consulted again.
static void NLCRefreshIdleTimer(void) {
    gLastActive = NLCShouldBeActive();
    SBIdleTimerGlobalCoordinator *coordinator = [%c(SBIdleTimerGlobalCoordinator) sharedInstanceIfExists];
    if (!coordinator) return;
    if ([coordinator respondsToSelector:@selector(_idleTimerPrefsChanged)]) {
        [coordinator _idleTimerPrefsChanged];
    } else if ([coordinator respondsToSelector:@selector(_updateIdleTimerForReason:)]) {
        [coordinator _updateIdleTimerForReason:@"NeverLockCC"];
    }
    if ([coordinator respondsToSelector:@selector(resetIdleTimerForReason:)]) {
        [coordinator resetIdleTimerForReason:@"NeverLockCC"];
    }
}

static void NLCPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL wasTimerEnabled = gTimerEnabled;
        NSTimeInterval oldSeconds = gTimerSeconds;
        NLCLoadPrefs();
        // A user re-enabling the timer or changing its value gets a fresh try.
        if ((gTimerEnabled && !wasTimerEnabled) || gTimerSeconds != oldSeconds) gCustomTimerFailed = NO;
        NLCRefreshIdleTimer();
    });
}

%hook SBIdleTimerDescriptorFactory

- (SBIdleTimerDescriptor *)idleTimerDescriptorForBehavior:(id)behavior {
    SBIdleTimerDescriptor *descriptor = %orig;
    if (!descriptor || !NLCShouldBeActive()) return descriptor;

    if (!gTimerEnabled) {
        SBIdleTimerDescriptor *disabled = [%c(SBIdleTimerDescriptorFactory) disabledIdleTimerDescriptor];
        return disabled ?: descriptor;
    }

    // Custom timeout. Only adjust a real, finite timer; if SpringBoard has
    // already disabled it (e.g. Auto-Lock set to Never) leave it alone.
    double total = descriptor.totalInterval;
    NLCInstallSafetyNet();
    // Never hand SpringBoard a custom timer unless a rejection can be caught.
    if (!gSafetyNetInstalled) {
        NLCLog(@"safety net not installed; using stock timer");
        return descriptor;
    }
    if (gCustomTimerFailed || !(total > 0) || !isfinite(total)) return descriptor;

    // Leave timers SpringBoard has disabled alone.
    SBIdleTimerDescriptor *disabled = [%c(SBIdleTimerDescriptorFactory) disabledIdleTimerDescriptor];
    if (disabled && descriptor.timerMode == disabled.timerMode) return descriptor;

    // The three intervals are absolute times from the last touch and become
    // timeouts that must be strictly increasing: dim (warn) < quick-unwarn <
    // lock (total). Stock 30s Auto-Lock is 20 / 22 / 30. Shift them together,
    // keeping the stock gaps: a 60s timer becomes 50 / 52 / 60.
    double T = gTimerSeconds;
    double warn = descriptor.warnInterval;
    double quick = descriptor.quickUnwarnInterval;
    SBIdleTimerDescriptor *custom = [descriptor copy];
    custom.totalInterval = T;
    if (warn > 0 && warn < total) {
        double lead = total - warn;
        double newWarn = lead < T ? T - lead : T * (warn / total);
        custom.warnInterval = newWarn;
        if (quick > warn && quick < total) {
            double newQuick = newWarn + (quick - warn);
            if (newQuick >= T) newQuick = newWarn + (T - newWarn) / 2;
            custom.quickUnwarnInterval = newQuick;
        }
    }
    NLCLog(@"timer %.0fs\n  stock:  %@\n  custom: %@", T, descriptor, custom);
    return custom;
}

%end

// Safety net: SpringBoard asserts (and crashes) in -setTimeouts: if the
// timeouts derived from a descriptor are invalid. If that happens with our
// custom timer, swallow it once, stop using the custom timer and have
// SpringBoard rebuild its stock timer.
%group SafetyNet
%hook ITIdleTimerDescriptor

- (void)setTimeouts:(NSArray *)timeouts {
    BOOL ours = gTimerEnabled && NLCShouldBeActive();
    if (ours) NLCLog(@"setTimeouts: %@", timeouts);
    @try {
        %orig;
    } @catch (NSException *exception) {
        // Not our custom timer: don't hide SpringBoard's own failures.
        if (gCustomTimerFailed || !ours) @throw;
        gCustomTimerFailed = YES;
        NLCLog(@"SpringBoard rejected custom timer: %@ — falling back to stock Auto-Lock, timer switched off", exception.reason);
        dispatch_async(dispatch_get_main_queue(), ^{
            NLCSetValue(kNLCKeyTimerEnabled, @NO);
        });
    }
}

%end
%end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    NLCInstallSafetyNet();
    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceBatteryStateDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if (NLCShouldBeActive() != gLastActive) NLCRefreshIdleTimer();
    }];
    NLCRefreshIdleTimer();
}

%end

// IdleTimerHosting may not be loaded yet when the tweak's constructor runs,
// so retry until ITIdleTimerDescriptor exists.
static void NLCInstallSafetyNet(void) {
    if (gSafetyNetInstalled || !objc_getClass("ITIdleTimerDescriptor")) return;
    %init(SafetyNet);
    gSafetyNetInstalled = YES;
    NLCLog(@"safety net installed");
}

%ctor {
    %init;
    NLCInstallSafetyNet();
    NLCLoadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NLCPrefsChanged,
                                    CFSTR(kNLCNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
