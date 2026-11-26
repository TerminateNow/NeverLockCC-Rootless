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
@end

@interface SBIdleTimerDescriptorFactory : NSObject
+ (SBIdleTimerDescriptor *)disabledIdleTimerDescriptor;
- (BOOL)updateIdleTimerSettingsForDuration:(long long)duration descriptor:(SBIdleTimerDescriptor *)descriptor;
- (BOOL)sanitizeWarnInterval:(SBIdleTimerDescriptor *)descriptor;
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
    if (gCustomTimerFailed || !(total > 0) || !isfinite(total)) return descriptor;

    SBIdleTimerDescriptor *custom = [descriptor copy];
    if ([self respondsToSelector:@selector(updateIdleTimerSettingsForDuration:descriptor:)]) {
        // Same path SpringBoard uses for the Auto-Lock setting, so the warn /
        // quick-unwarn intervals stay consistent with the new total.
        [self updateIdleTimerSettingsForDuration:(long long)gTimerSeconds descriptor:custom];
    } else {
        double scale = gTimerSeconds / total;
        custom.totalInterval = gTimerSeconds;
        custom.warnInterval = descriptor.warnInterval * scale;
        custom.quickUnwarnInterval = descriptor.quickUnwarnInterval * scale;
    }
    if ([self respondsToSelector:@selector(sanitizeWarnInterval:)]) {
        [self sanitizeWarnInterval:custom];
    }
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
    @try {
        %orig;
    } @catch (NSException *exception) {
        // Not our custom timer: don't hide SpringBoard's own failures.
        if (gCustomTimerFailed || !gTimerEnabled || !NLCShouldBeActive()) @throw;
        gCustomTimerFailed = YES;
        NSLog(@"[NeverLockCC] SpringBoard rejected custom timer (%@); falling back to stock Auto-Lock", exception.reason);
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

%ctor {
    %init;
    if (objc_getClass("ITIdleTimerDescriptor")) %init(SafetyNet);
    NLCLoadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NLCPrefsChanged,
                                    CFSTR(kNLCNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
