#!/bin/bash
# 构建可发布的 codedog：通用二进制（arm64 + x86_64）、ad-hoc 签名，产出 dmg / zip / SHA256SUMS。
# 用法：scripts/release.sh            产物在 release/
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -nE 's/^ *MARKETING_VERSION: *"?([0-9][^"]*)"?.*/\1/p' project.yml | head -1)
[[ -n "$VERSION" ]] || { echo "无法从 project.yml 读取 MARKETING_VERSION" >&2; exit 1; }
echo "==> codedog $VERSION"

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

APP="$DERIVED/Build/Products/Release/codedog.app"
[[ -d "$APP" ]] || { echo "构建失败：找不到 $APP" >&2; exit 1; }

echo "==> 校验"
for bin in "$APP/Contents/MacOS/codedog" "$APP/Contents/MacOS/codedog-cli"; do
  archs=$(lipo -archs "$bin")
  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || { echo "$bin 不是通用二进制：$archs" >&2; exit 1; }
done
codesign --verify --deep --strict "$APP"
plist_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
[[ "$plist_version" == "$VERSION" ]] || { echo "版本不一致：Info.plist=$plist_version project.yml=$VERSION" >&2; exit 1; }
"$APP/Contents/MacOS/codedog-cli" --version | grep -qx "$VERSION"

echo "==> 打包"
mkdir -p release
NAME="codedog-$VERSION-mac-universal"
ditto -c -k --keepParent "$APP" "release/$NAME.zip"

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "codedog $VERSION" -srcfolder "$STAGE" -ov -format UDZO "release/$NAME.dmg"
rm -rf "$STAGE"

(cd release && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt)
ls -lh release
echo "==> 完成：release/$NAME.{dmg,zip}"
