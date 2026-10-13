# Blottle — build helpers. Run on macOS 14+ with Xcode (or the Command Line Tools).

APP_NAME     := Blottle
BUILD_DIR    := build
TOOLS_DIR    := $(BUILD_DIR)/tools
WRAPPER_SRC  := tools/steamwebhelper-wrapper
GOFLAGS      := -trimpath -ldflags="-s -w -H windowsgui"

.PHONY: all build release test cli app wrapper install-cli clean run

all: build

## Debug build of everything (kit, CLI, app).
build:
	swift build

## Optimised build.
release:
	swift build -c release

## Unit tests.
test:
	swift test

## Build only the command-line tool.
cli:
	swift build -c release --product blottle
	@echo "Binário em .build/release/blottle"

## Installs the CLI into /usr/local/bin (may ask for sudo).
install-cli: cli
	install -m 755 .build/release/blottle /usr/local/bin/blottle

## Windows wrappers for steamwebhelper.exe (needs Go: brew install go).
wrapper:
	mkdir -p $(TOOLS_DIR)
	cd $(WRAPPER_SRC) && GOOS=windows GOARCH=amd64 go build $(GOFLAGS) -o ../../$(TOOLS_DIR)/steamwebhelper-wrapper-x64.exe .
	cd $(WRAPPER_SRC) && GOOS=windows GOARCH=386   go build $(GOFLAGS) -o ../../$(TOOLS_DIR)/steamwebhelper-wrapper-x86.exe .
	@echo "Wrappers em $(TOOLS_DIR)"

## Blottle.app bundle in build/ (includes the wrappers when Go is available).
app: release
	-$(MAKE) wrapper
	scripts/make-app.sh $(BUILD_DIR)

## Launch the SwiftUI app straight from the package (no bundle).
run:
	swift run BlottleApp

clean:
	rm -rf .build $(BUILD_DIR)
