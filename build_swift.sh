#!/bin/bash
# 打包 JPG转PSD.app（macOS / Apple Silicon）
# 纯 Swift + AppKit 实现，产物自包含，不需要 Python 运行时。
# 产物：本目录下的 JPG转PSD.app
set -euo pipefail
cd "$(dirname "$0")"

APP_OUT="JPG转PSD.app"
APP_INNER="JPG2PSD"
TARGET="arm64-apple-macos13.0"
WORK="/tmp/jpg2psd-swift-build"

echo "==> 1/4 准备构建目录"
rm -rf "$WORK" "$APP_OUT"
mkdir -p "$WORK"

echo "==> 2/4 编译 Swift 源码"
# shellcheck disable=SC2086
swiftc -O -swift-version 5 -target "$TARGET" -framework AppKit \
  Sources/*.swift -o "$WORK/$APP_INNER"

echo "==> 3/4 组装 App 包"
mkdir -p "$APP_OUT/Contents/MacOS" "$APP_OUT/Contents/Resources"
cp "$WORK/$APP_INNER" "$APP_OUT/Contents/MacOS/$APP_INNER"
cp Sources/Info.plist "$APP_OUT/Contents/Info.plist"
printf 'APPL????' > "$APP_OUT/Contents/PkgInfo"

if [ -f assets/icon.icns ]; then
  cp assets/icon.icns "$APP_OUT/Contents/Resources/icon.icns"
  echo "    已内置图标 assets/icon.icns"
else
  echo "    警告：assets/icon.icns 不存在，将使用系统默认图标"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP_OUT/Contents/Info.plist" || true
fi

echo "==> 4/4 临时签名（本机运行）"
codesign --force --deep --sign - "$APP_OUT" 2>&1 | tail -2 || true
codesign --verify --verbose=1 "$APP_OUT" 2>&1 | tail -3 || true

echo
echo "完成：$PWD/$APP_OUT"
echo "  架构: $(lipo -archs "$APP_OUT/Contents/MacOS/$APP_INNER" 2>/dev/null || echo 未知)"
echo "  大小: $(du -sh "$APP_OUT" | cut -f1)"
