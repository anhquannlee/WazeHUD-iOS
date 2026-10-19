include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = WazeHUDPrefs

WazeHUDPrefs_FILES = WazeHUDPrefsRootListController.m
WazeHUDPrefs_INSTALL_PATH = /Library/PreferenceBundles
WazeHUDPrefs_FRAMEWORKS = UIKit
WazeHUDPrefs_RESOURCE_DIRS = Resources
WazeHUDPrefs_CFLAGS = -fobjc-arc

# Trỏ chính xác vào iPhoneOS16.5.sdk vừa check được
ADDITIONAL_CFLAGS += -F$(THEOS)/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks
ADDITIONAL_LDFLAGS += -F$(THEOS)/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks
WazeHUDPrefs_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk