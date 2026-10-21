TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LiquidMenuPrefs

LiquidMenuPrefs_FILES = LMRootListController.m LMAppsListController.m
LiquidMenuPrefs_FRAMEWORKS = UIKit
LiquidMenuPrefs_PRIVATE_FRAMEWORKS = Preferences
LiquidMenuPrefs_INSTALL_PATH = /Library/PreferenceBundles
LiquidMenuPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/bundle.mk
