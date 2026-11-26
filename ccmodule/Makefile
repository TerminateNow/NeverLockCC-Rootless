TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NeverLockCCModule
NeverLockCCModule_BUNDLE_EXTENSION = bundle
NeverLockCCModule_FILES = NLCModule.m
NeverLockCCModule_CFLAGS = -fobjc-arc
NeverLockCCModule_FRAMEWORKS = UIKit
NeverLockCCModule_PRIVATE_FRAMEWORKS = ControlCenterUIKit
NeverLockCCModule_INSTALL_PATH = /Library/ControlCenter/Bundles

include $(THEOS_MAKE_PATH)/bundle.mk
