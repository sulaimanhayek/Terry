APP  := build/Terry.app
BIN  := .build/release/Terry
# Ad-hoc by default. Pass an identity (e.g. SIGN="Apple Development: you@example.com")
# so macOS keeps granted permissions across rebuilds.
SIGN ?= -
# Command Line Tools (no Xcode) need explicit paths to Swift Testing.
DEV  := $(shell xcode-select -p)
ifneq (,$(findstring CommandLineTools,$(DEV)))
TESTFLAGS := -Xswiftc -F -Xswiftc $(DEV)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(DEV)/Library/Developer/Frameworks \
	-Xlinker -rpath -Xlinker $(DEV)/Library/Developer/usr/lib
endif

.PHONY: build app run test icon install clean

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Terry
	cp App/Info.plist $(APP)/Contents/Info.plist
	[ -f App/AppIcon.icns ] && cp App/AppIcon.icns $(APP)/Contents/Resources/ || true
	codesign --force --options runtime --entitlements App/Terry.entitlements --sign "$(SIGN)" $(APP)

run: app
	open $(APP)

test:
	swift test $(TESTFLAGS) $(if $(FILTER),--filter '$(FILTER)')

icon:
	swift scripts/make-icon.swift

install: app
	rm -rf /Applications/Terry.app
	cp -R $(APP) /Applications/

clean:
	rm -rf .build build
