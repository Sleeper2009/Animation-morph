TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

# Mặc định build rootless (Dopamine, palera1n rootless...).
# Rootful (checkra1n, unc0ver, Taurine...):
#   - đổi dòng Architecture trong control thành iphoneos-arm
#   - make clean package THEOS_PACKAGE_SCHEME=
# (GitHub Actions trong .github/workflows/build.yml tự làm cả hai việc này.)
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LiquidMenu
LiquidMenu_FILES = Tweak.x LGMenuMorph.m LGLog.m LGMetaball.c LGRing.m
LiquidMenu_FRAMEWORKS = UIKit QuartzCore CoreGraphics CoreImage
LiquidMenu_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk

# Gói Cài đặt: thư mục liquidmenuprefs/ + layout/Library/PreferenceLoader/
SUBPROJECTS += liquidmenuprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
