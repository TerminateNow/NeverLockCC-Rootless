// NeverLockCC — Control Center module (loaded by CCSupport).
//
// Tap: turn the tweak on/off.
// Long press: expands into a menu with
//   • Charging Required / Always On (mode, pick one)
//   • Timer (<saved value>)        (on/off)
// Every change is written to the shared prefs domain and broadcast, so the
// Settings pane and the SpringBoard tweak pick it up immediately, and changes
// made in Settings update this module the same way.

#import <UIKit/UIKit.h>
#import "../Shared/NLCPrefs.h"

@interface CCUIButtonModuleViewController : UIViewController
@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic, retain) UIImage *glyphImage;
@property (nonatomic, retain) UIImage *selectedGlyphImage;
@property (nonatomic, retain) UIColor *selectedGlyphColor;
@property (nonatomic, getter=isExpanded) BOOL expanded;
- (void)buttonTapped:(id)button forEvent:(id)event;
- (void)willTransitionToExpandedContentMode:(BOOL)expanded;
@end

@interface CCUIMenuModuleViewController : CCUIButtonModuleViewController
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic) BOOL useTrailingCheckmarkLayout;
- (void)setMenuItems:(NSArray *)items;
@end

@interface CCUIMenuModuleItem : NSObject
@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic, copy) NSString *identifier;
- (instancetype)initWithTitle:(NSString *)title identifier:(NSString *)identifier handler:(BOOL (^)(void))handler;
@end

@protocol CCUIContentModule <NSObject>
@optional
@property (nonatomic, readonly) UIViewController *contentViewController;
@end

#pragma mark - View controller

@interface NLCModuleViewController : CCUIMenuModuleViewController
- (void)reloadState;
@end

static void NLCPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NLCModuleViewController *controller = (__bridge NLCModuleViewController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller reloadState];
    });
}

@implementation NLCModuleViewController

- (instancetype)initWithNibName:(NSString *)nibName bundle:(NSBundle *)bundle {
    if ((self = [super initWithNibName:nibName bundle:bundle])) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                        NLCPrefsChanged, CFSTR(kNLCNotification), NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                       CFSTR(kNLCNotification), NULL);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // 30% larger than the default symbol size (17 pt).
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17.0 * 1.3];
    UIImage *bolt = [UIImage systemImageNamed:@"bolt.fill" withConfiguration:config];
    self.glyphImage = bolt;
    self.selectedGlyphImage = bolt;
    self.selectedGlyphColor = [UIColor systemOrangeColor];
    self.title = @"NeverLock";
    if ([self respondsToSelector:@selector(setUseTrailingCheckmarkLayout:)]) {
        self.useTrailingCheckmarkLayout = YES;
    }
    [self reloadState];
}

- (BOOL)_canShowWhileLocked {
    return YES;
}

// White SF Symbol shown on the left of each menu row.
- (UIImage *)leadingImageForMenuItem:(CCUIMenuModuleItem *)item {
    NSString *identifier = item.identifier;
    NSArray<NSString *> *names = nil;
    if ([identifier isEqualToString:kNLCMenuItemPrefix @"chargingRequired"]) {
        names = @[@"battery.100.bolt", @"battery.100"];
    } else if ([identifier isEqualToString:kNLCMenuItemPrefix @"alwaysOn"]) {
        names = @[@"infinity"];
    } else if ([identifier isEqualToString:kNLCMenuItemPrefix @"timer"]) {
        names = @[@"stopwatch", @"timer"];
    }
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIImageSymbolWeightMedium];
    for (NSString *name in names) {
        UIImage *image = [UIImage systemImageNamed:name withConfiguration:config];
        if (image) return [image imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    return nil;
}

- (void)buttonTapped:(id)button forEvent:(id)event {
    BOOL enabled = !NLCGetBool(kNLCKeyEnabled, YES);
    NLCSetValue(kNLCKeyEnabled, @(enabled));
    [self reloadState];
}

- (void)willTransitionToExpandedContentMode:(BOOL)expanded {
    [super willTransitionToExpandedContentMode:expanded];
    if (expanded) [self reloadState];
}

- (void)reloadState {
    BOOL enabled = NLCGetBool(kNLCKeyEnabled, YES);
    BOOL alwaysOn = NLCGetBool(kNLCKeyAlwaysOn, NO);
    BOOL timerEnabled = NLCGetBool(kNLCKeyTimerEnabled, NO);
    NSString *timerString = NLCGetTimerString();

    self.selected = enabled;
    self.subtitle = enabled ? (alwaysOn ? @"On · Always On" : @"On · Charging Required") : @"Off";

    __weak NLCModuleViewController *weakSelf = self;
    BOOL (^set)(NSString *, id) = ^BOOL(NSString *key, id value) {
        NLCSetValue(key, value);
        // Rebuild on the next runloop pass rather than inside the item's own handler.
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reloadState]; });
        return NO; // keep the menu open
    };

    // Identifiers carry kNLCMenuItemPrefix so the SpringBoard tweak can keep
    // these rows' text left-aligned (see CCUIMenuModuleItemView hook in Tweak.x).
    CCUIMenuModuleItem *charging = [[CCUIMenuModuleItem alloc] initWithTitle:@"Charging Required"
                                                                 identifier:kNLCMenuItemPrefix @"chargingRequired"
                                                                    handler:^BOOL { return set(kNLCKeyAlwaysOn, @NO); }];
    charging.selected = !alwaysOn;

    CCUIMenuModuleItem *always = [[CCUIMenuModuleItem alloc] initWithTitle:@"Always On"
                                                               identifier:kNLCMenuItemPrefix @"alwaysOn"
                                                                  handler:^BOOL { return set(kNLCKeyAlwaysOn, @YES); }];
    always.selected = alwaysOn;

    NSString *timerTitle = [NSString stringWithFormat:@"Timer (%@)", timerString];
    CCUIMenuModuleItem *timer = [[CCUIMenuModuleItem alloc] initWithTitle:timerTitle
                                                              identifier:kNLCMenuItemPrefix @"timer"
                                                                 handler:^BOOL { return set(kNLCKeyTimerEnabled, @(!timerEnabled)); }];
    timer.selected = timerEnabled;

    [self setMenuItems:@[charging, always, timer]];
}

@end

#pragma mark - Module

@interface NLCModule : NSObject <CCUIContentModule>
@end

@implementation NLCModule {
    NLCModuleViewController *_contentViewController;
}

- (instancetype)init {
    if ((self = [super init])) {
        _contentViewController = [[NLCModuleViewController alloc] initWithNibName:nil bundle:nil];
    }
    return self;
}

- (UIViewController *)contentViewController {
    return _contentViewController;
}

@end
