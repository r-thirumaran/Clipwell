# SnapBoard — build, test and install.
#
# Two build paths, same output bundle:
#   * `xcodebuild` when a full Xcode is installed (the path the project was specified around)
#   * `Tools/build.sh` (swiftc + codesign) when only the Command Line Tools are present
#
# `make build` picks whichever is available, so neither is a prerequisite for the other.

APP_NAME    := SnapBoard
BUNDLE_ID   := com.thiru.snapboard
BUILD_DIR   := build
APP         := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := /Applications
INSTALLED   := $(INSTALL_DIR)/$(APP_NAME).app
CONFIG      := Release

HAS_XCODE := $(shell xcodebuild -version >/dev/null 2>&1 && echo yes)

.PHONY: help
help:
	@echo "SnapBoard"
	@echo ""
	@echo "  make build      Build $(APP_NAME).app into ./$(BUILD_DIR)"
	@echo "  make install    Build and install to $(INSTALL_DIR)"
	@echo "  make uninstall  Remove $(INSTALLED)"
	@echo "  make run        Launch the built app"
	@echo "  make stop       Quit any running instance"
	@echo "  make test       Run the clipboard smoke tests"
	@echo "  make project    Regenerate $(APP_NAME).xcodeproj from the sources on disk"
	@echo "  make clean      Delete ./$(BUILD_DIR)"
	@echo ""
ifeq ($(HAS_XCODE),yes)
	@echo "  Build backend:  xcodebuild (full Xcode detected)"
else
	@echo "  Build backend:  swiftc via Tools/build.sh (no full Xcode detected)"
	@echo "                  Install Xcode to use the xcodebuild path."
endif

# ---------------------------------------------------------------------------- build

.PHONY: build
ifeq ($(HAS_XCODE),yes)
build:
	xcodebuild -project $(APP_NAME).xcodeproj \
	           -scheme $(APP_NAME) \
	           -configuration $(CONFIG) \
	           -derivedDataPath $(BUILD_DIR)/DerivedData \
	           build
	@rm -rf "$(APP)"
	@mkdir -p "$(BUILD_DIR)"
	@cp -R "$(BUILD_DIR)/DerivedData/Build/Products/$(CONFIG)/$(APP_NAME).app" "$(APP)"
	@echo "==> Built $(APP)"
else
build:
	@Tools/build.sh release
endif

.PHONY: project
project:
	@python3 Tools/generate_xcodeproj.py

# ---------------------------------------------------------------------------- install

.PHONY: install
install: build stop
	@# Only ever replace a bundle that is actually SnapBoard — never blindly rm -rf a path
	@# under /Applications.
	@if [ -e "$(INSTALLED)" ]; then \
		existing=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
			"$(INSTALLED)/Contents/Info.plist" 2>/dev/null); \
		if [ "$$existing" != "$(BUNDLE_ID)" ]; then \
			echo "refusing to replace $(INSTALLED): bundle id is '$$existing', expected '$(BUNDLE_ID)'"; \
			exit 1; \
		fi; \
		rm -rf "$(INSTALLED)"; \
	fi
	@cp -R "$(APP)" "$(INSTALLED)"
	@echo ""
	@echo "==> Installed $(INSTALLED)"
	@echo ""
	@echo "  ┌──────────────────────────────────────────────────────────────────────┐"
	@echo "  │  One more step: grant Accessibility access                            │"
	@echo "  └──────────────────────────────────────────────────────────────────────┘"
	@echo ""
	@echo "  SnapBoard cannot move windows or paste for you until macOS allows it."
	@echo ""
	@echo "    1. Open SnapBoard:      open $(INSTALLED)"
	@echo "    2. It opens a setup window with a button to the right settings pane."
	@echo "       (Or go there directly: System Settings > Privacy & Security >"
	@echo "        Accessibility.)"
	@echo "    3. Turn ON the switch next to SnapBoard."
	@echo ""
	@echo "  If SnapBoard is ALREADY in that list from an earlier build, select it,"
	@echo "  press '-' to remove it, then add the new copy. macOS ties the permission"
	@echo "  to the code signature, and an ad-hoc signature changes on every rebuild."
	@echo ""
	@echo "  Then: click the menu bar icon, or press Ctrl+Cmd+Left to snap a window."
	@echo ""

.PHONY: uninstall
uninstall: stop
	@if [ -e "$(INSTALLED)" ]; then rm -rf "$(INSTALLED)"; echo "removed $(INSTALLED)"; \
	else echo "$(INSTALLED) is not installed"; fi
	@echo "note: clipboard history in ~/Library/Application Support/$(APP_NAME) was left in place"

# ---------------------------------------------------------------------------- run / test

.PHONY: run
run: build
	@open "$(APP)"

.PHONY: stop
stop:
	@pkill -x $(APP_NAME) 2>/dev/null || true

.PHONY: test
test: build
	@Tools/smoketest.sh

.PHONY: clean
clean:
	@rm -rf "$(BUILD_DIR)"
	@echo "cleaned $(BUILD_DIR)"

# ---------------------------------------------------------------------------- distribution

VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
DMG     := $(BUILD_DIR)/SnapBoard-$(VERSION).dmg
STAGE   := $(BUILD_DIR)/dmg-stage

## Build a drag-to-install disk image for sharing with other people.
.PHONY: dmg
dmg: build
	@rm -rf "$(STAGE)" "$(DMG)"
	@mkdir -p "$(STAGE)"
	@cp -R "$(APP)" "$(STAGE)/"
	@ln -s /Applications "$(STAGE)/Applications"
	@cp dist/READ-ME-FIRST.txt "$(STAGE)/" 2>/dev/null || true
	@hdiutil create -volname "SnapBoard $(VERSION)" -srcfolder "$(STAGE)" \
		-ov -format UDZO "$(DMG)" >/dev/null
	@rm -rf "$(STAGE)"
	@echo "==> $(DMG)  ($$(du -h '$(DMG)' | cut -f1))"
	@echo ""
	@echo "    Ad-hoc signed. Recipients MUST run this after copying to /Applications:"
	@echo "      xattr -dr com.apple.quarantine /Applications/SnapBoard.app"
	@echo "    See dist/DISTRIBUTION.md for the Developer ID path that removes that step."

## Report what kind of signature the built app carries.
.PHONY: signing-status
signing-status: build
	@echo "== signature =="
	@codesign -dv --verbose=2 "$(APP)" 2>&1 | grep -E 'Authority|Signature|TeamIdentifier|flags' || true
	@echo ""
	@echo "== notarization =="
	@spctl -a -vvv -t install "$(APP)" 2>&1 || true
	@echo ""
	@echo "== available identities =="
	@security find-identity -v -p codesigning 2>/dev/null | grep -E 'Developer ID|Apple Development' \
		|| echo "  (none — ad-hoc signing only)"
