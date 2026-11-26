# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

NeverLockCC: a rootless (Dopamine, `/var/jb`) Theos tweak for iOS 15 that keeps the screen on while charging (or always), with a Settings pane and a CCSupport Control Center module. Package scheme is `rootless`, arch `iphoneos-arm64`.

## Build

```bash
export THEOS=~/theos
make package FINALPACKAGE=1    # .deb lands in packages/
```

`make do` installs to a device over SSH (set `THEOS_DEVICE_IP`). There are no tests; changes must be verified on a device.

Build arm64e on macOS/Xcode (see `.github/workflows/build.yml`). The Linux Theos toolchain compiles but emits the old arm64e ABI (`ld: warning: ... incompatible arm64e ABI`), which iOS 14+ arm64e processes may refuse to load.

## Architecture

Three Theos targets share one preference domain, `com.terminatenow.neverlockcc`, through `Shared/NLCPrefs.h` (keys, defaults, timer parsing, write + Darwin notify). Every write goes through `NLCSetValue`, which posts `com.terminatenow.neverlockcc/prefsChanged`; each target listens for it. That is the whole sync mechanism, so new settings must use the same helpers.

- `Tweak.x` (SpringBoard): hooks `-[SBIdleTimerDescriptorFactory idleTimerDescriptorForBehavior:]`. When active it returns `+disabledIdleTimerDescriptor` (never lock) or a copy with `totalInterval` set to the custom timer. On a prefs or battery-state change it calls `SBIdleTimerGlobalCoordinator _idleTimerPrefsChanged` so SpringBoard rebuilds the descriptor.
- `prefs/` (Preferences bundle): overrides `readPreferenceValue:` / `setPreferenceValue:specifier:` to use the shared helpers. It reloads only when the stored values differ from what's shown, so its own writes don't reset the text field.
- `ccmodule/` (CCSupport bundle, subclasses `CCUIMenuModuleViewController`): tap toggles `enabled`; long press shows the mode and timer menu items, rebuilt from prefs on every change.

Private SpringBoard/ControlCenterUIKit interfaces are declared inline in each file (from iOS 14.5 header dumps; iOS 15 is assumed to match).
