#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../Shared/NLCPrefs.h"

@interface NLCRootListController : PSListController
@property (nonatomic, copy) NSDictionary *shownValues;
- (void)reloadIfChangedElsewhere;
@end

static NSDictionary *NLCCurrentValues(void) {
    return @{
        kNLCKeyEnabled: @(NLCGetBool(kNLCKeyEnabled, YES)),
        kNLCKeyAlwaysOn: @(NLCGetBool(kNLCKeyAlwaysOn, NO)),
        kNLCKeyTimerEnabled: @(NLCGetBool(kNLCKeyTimerEnabled, NO)),
        kNLCKeyTimerValue: NLCGetTimerString(),
    };
}

static void NLCPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NLCRootListController *controller = (__bridge NLCRootListController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller reloadIfChangedElsewhere];
    });
}

@implementation NLCRootListController

- (instancetype)init {
    if ((self = [super init])) {
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

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        self.shownValues = NLCCurrentValues();
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadIfChangedElsewhere];
}

// Only reload when the stored values differ from what this pane shows, so our
// own writes (which also post the notification) never reset the page while
// the user is typing in the timer field.
- (void)reloadIfChangedElsewhere {
    NSDictionary *current = NLCCurrentValues();
    if ([current isEqualToDictionary:self.shownValues]) return;
    self.shownValues = current;
    [self reloadSpecifiers];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:kNLCKeyTimerValue]) return NLCGetTimerString();
    id value = NLCCopyValue(key);
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    if ([key isEqualToString:kNLCKeyTimerValue]) {
        NSString *string = [[value description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        value = string.length ? string : kNLCDefaultTimerValue;
    }
    NLCSetValue(key, value);
    self.shownValues = NLCCurrentValues();
}

@end
