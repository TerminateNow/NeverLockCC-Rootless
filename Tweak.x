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
        NLCLoadPrefs();
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

    // Custom timeout. Only stretch a real, finite timer; if SpringBoard has
    // already disabled it (e.g. Auto-Lock set to Never) leave it alone.
    double total = descriptor.totalInterval;
    if (!(total > 0) || !isfinite(total)) return descriptor;

    SBIdleTimerDescriptor *custom = [descriptor copy];
    double scale = gTimerSeconds / total;
    custom.totalInterval = gTimerSeconds;
    // Keep the dim warning at the same relative point in the countdown.
    custom.warnInterval = descriptor.warnInterval * scale;
    return custom;
}

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
    NLCLoadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NLCPrefsChanged,
                                    CFSTR(kNLCNotification), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
