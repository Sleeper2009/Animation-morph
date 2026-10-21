TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LiquidMenuPrefs

LiquidMenuPrefs_FILES = LMRootListController.m LMAppsListController.m
LiquidMenuPrefs_FRAMEWORKS = UIKit
LiquidMenuPrefs_INSTALL_PATH = /Library/PreferenceBundles
LiquidMenuPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
# SDK trên GitHub Actions không có PrivateFrameworks nên không link được framework Preferences.
# Các lớp PSListController / PSSpecifier... được tìm lúc chạy (ứng dụng Cài đặt đã nạp sẵn Preferences.framework).
LiquidMenuPrefs_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
