TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NeverLockCC
NeverLockCC_FILES = Tweak.x
NeverLockCC_CFLAGS = -fobjc-arc
NeverLockCC_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs ccmodule
include $(THEOS_MAKE_PATH)/aggregate.mk
