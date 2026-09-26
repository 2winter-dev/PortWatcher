#!/usr/bin/env bash
# PortWatcher 打包成 .dmg（标准「拖到 Applications 安装」极简 DMG）
#
# 推荐发布顺序：
#   1) bash notarize.sh     # 用 Developer ID 签名（hardened runtime，不开沙箱）
#   2) bash make-dmg.sh     # 把签名后的 .app 包成 .dmg
#   3) （可选）xcrun notarytool submit PortWatcher.dmg ...   # 连 dmg 一起公证更稳
#
# 仅打包、不签名：本脚本对已有 build/PortWatcher.app 直接封装，签名交给 notarize.sh。
set -euo pipefail
cd "$(dirname "$0")"

APP="build/PortWatcher.app"
DMG="PortWatcher.dmg"
VOL="PortWatcher"
STAGE="build/dmg-staging"

test -d "$APP" || { echo "找不到 $APP：先 swift build -c release --disable-sandbox 并装配 .app"; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

# 拖拽安装用的 Applications 替身（用户把 app 拖上去即安装）
ln -s /Applications "$STAGE/Applications"

# 生成压缩只读 DMG
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -format UDZO -ov "$DMG"

rm -rf "$STAGE"
echo "==> 完成：$DMG  ($(du -h "$DMG" | cut -f1))"
