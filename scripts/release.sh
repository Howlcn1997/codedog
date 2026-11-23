#!/bin/bash
# 构建可发布的 CodeDog：通用二进制（arm64 + x86_64）、ad-hoc 签名，产出 dmg / zip / SHA256SUMS。
# 用法：scripts/release.sh            产物在 release/
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -nE 's/^ *MARKETING_VERSION: *"?([0-9][^"]*)"?.*/\1/p' project.yml | head -1)
[[ -n "$VERSION" ]] || { echo "无法从 project.yml 读取 MARKETING_VERSION" >&2; exit 1; }
echo "==> CodeDog $VERSION"

command -v xcodegen >/dev/null || { echo "需要 xcodegen：brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

DERIVED=build/Release
rm -rf "$DERIVED" release
mkdir -p build
LOG=build/xcodebuild-release.log
# 不用 -quiet：新版 xcodebuild 在 -quiet 下会把成功的编译任务误报为 "exit code 0" 错误
if ! xcodebuild -project codedog.xcodeproj -scheme codedog -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | head -20 >&2 || true
  tail -20 "$LOG" >&2
  echo "构建失败，完整日志：$LOG" >&2
  exit 1
fi
grep -E "^\*\* BUILD" "$LOG"

APP="$DERIVED/Build/Products/Release/CodeDog.app"
[[ -d "$APP" ]] || { echo "构建失败：找不到 $APP" >&2; exit 1; }

echo "==> 校验"
for bin in "$APP/Contents/MacOS/CodeDog" "$APP/Contents/MacOS/codedog-cli"; do
  archs=$(lipo -archs "$bin")
  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || { echo "$bin 不是通用二进制：$archs" >&2; exit 1; }
done
codesign --verify --deep --strict "$APP"
plist_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
[[ "$plist_version" == "$VERSION" ]] || { echo "版本不一致：Info.plist=$plist_version project.yml=$VERSION" >&2; exit 1; }
"$APP/Contents/MacOS/codedog-cli" --version | grep -qx "$VERSION"

echo "==> 打包"
mkdir -p release
NAME="CodeDog-$VERSION-mac-universal"
ditto -c -k --keepParent "$APP" "release/$NAME.zip"

# dmg 安装窗口（背景图、图标位置、隐藏工具栏）用 dmgbuild 直接写 .DS_Store，不依赖 Finder，CI 上也稳定
DMGENV=build/dmgenv
if [[ ! -x "$DMGENV/bin/dmgbuild" ]]; then
  python3 -m venv "$DMGENV"
  "$DMGENV/bin/pip" install --quiet --disable-pip-version-check dmgbuild==1.6.1
fi
"$DMGENV/bin/dmgbuild" -s scripts/dmg/settings.py -D app="$APP" -D background=scripts/dmg/background.tiff \
  "CodeDog $VERSION" "release/$NAME.dmg" 2>&1 | grep -v "deprecated" || true
[[ -f "release/$NAME.dmg" ]] || { echo "dmg 打包失败" >&2; exit 1; }

(cd release && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt)
ls -lh release
echo "==> 完成：release/$NAME.{dmg,zip}"
