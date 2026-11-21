DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/codedog.app

.PHONY: project build test run clean

project:
	xcodegen generate

build: project
	xcodebuild -project codedog.xcodeproj -scheme codedog -configuration Debug -derivedDataPath $(DERIVED) build -quiet

test:
	cd Packages/CodedogCore && swift test

run: build
	open $(APP)

clean:
	rm -rf build codedog.xcodeproj
