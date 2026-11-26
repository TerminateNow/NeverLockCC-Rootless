// Shared preference helpers used by the SpringBoard tweak, the Settings pane
// and the Control Center module. All three read and write the same
// CFPreferences domain and post the same Darwin notification after a write,
// which is what keeps them in sync.

#import <Foundation/Foundation.h>
#include <notify.h>

#define kNLCDomain        CFSTR("com.terminatenow.neverlockcc")
#define kNLCNotification  "com.terminatenow.neverlockcc/prefsChanged"

#define kNLCKeyEnabled      @"enabled"       // BOOL, default YES
#define kNLCKeyAlwaysOn     @"alwaysOn"      // BOOL, default NO
#define kNLCKeyTimerEnabled @"timerEnabled"  // BOOL, default NO
#define kNLCKeyTimerValue   @"timerValue"    // NSString, default "10m"

// Prefix for the Control Center menu item identifiers.
#define kNLCMenuItemPrefix @"com.terminatenow.neverlockcc."

#define kNLCDefaultTimerValue   @"10m"
#define kNLCDefaultTimerSeconds 600.0

static inline id NLCCopyValue(NSString *key) {
    CFPreferencesAppSynchronize(kNLCDomain);
    return (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kNLCDomain);
}

static inline BOOL NLCGetBool(NSString *key, BOOL fallback) {
    id value = NLCCopyValue(key);
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static inline NSString *NLCGetTimerString(void) {
    id value = NLCCopyValue(kNLCKeyTimerValue);
    if ([value isKindOfClass:[NSNumber class]]) value = [value stringValue];
    NSString *string = [value isKindOfClass:[NSString class]] ? value : nil;
    string = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return string.length ? string : kNLCDefaultTimerValue;
}

// "600" -> 600 seconds, "10m" -> 600 seconds. Returns 0 for anything invalid.
static inline NSTimeInterval NLCParseTimerString(NSString *string) {
    NSString *s = [[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    double multiplier = 1.0;
    if ([s hasSuffix:@"m"]) {
        multiplier = 60.0;
        s = [s substringToIndex:s.length - 1];
    }
    NSScanner *scanner = [NSScanner scannerWithString:s];
    double number = 0;
    if (s.length == 0 || ![scanner scanDouble:&number] || !scanner.isAtEnd || number <= 0) return 0;
    return number * multiplier;
}

static inline NSTimeInterval NLCGetTimerSeconds(void) {
    NSTimeInterval seconds = NLCParseTimerString(NLCGetTimerString());
    return seconds > 0 ? seconds : kNLCDefaultTimerSeconds;
}

static inline void NLCSetValue(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kNLCDomain);
    CFPreferencesAppSynchronize(kNLCDomain);
    notify_post(kNLCNotification);
}
