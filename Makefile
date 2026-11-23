DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/CodeDog.app

.PHONY: project build test run dist clean

# 生成 Xcode 工程（codedog.xcodeproj 不入库）
project:
	xcodegen generate --quiet

# 调试构建（数据默认写到 ~/Library/Application Support/codedog-dev）
build: project
	@mkdir -p build
	@xcodebuild -project codedog.xcodeproj -scheme codedog -configuration Debug -destination 'generic/platform=macOS' \
		-derivedDataPath $(DERIVED) build > build/xcodebuild.log 2>&1 \
		|| (grep -aE "error:" build/xcodebuild.log | head -20; tail -20 build/xcodebuild.log; exit 1)
	@grep -aE "^\*\* BUILD" build/xcodebuild.log

test:
	cd Packages/CodedogCore && swift test

run: build
	open $(APP)

# 发布包：通用二进制 + ad-hoc 签名，产出 release/*.dmg|zip
dist:
	scripts/release.sh

clean:
	rm -rf build release codedog.xcodeproj
