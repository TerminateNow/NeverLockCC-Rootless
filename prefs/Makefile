TARGET := iphone:clang:15.6:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NeverLockCCPrefs
NeverLockCCPrefs_FILES = NLCRootListController.m
NeverLockCCPrefs_FRAMEWORKS = UIKit
NeverLockCCPrefs_PRIVATE_FRAMEWORKS = Preferences
NeverLockCCPrefs_INSTALL_PATH = /Library/PreferenceBundles
NeverLockCCPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
