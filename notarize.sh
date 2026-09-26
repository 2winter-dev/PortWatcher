#!/usr/bin/env bash
# PortWatcher 发布脚本：Developer ID 签名 + 公证（notarization），不走 Mac App Store
#
# 前提（需你本机准备）：
#   1) 钥匙串里装好 "Developer ID Application: <Team Name> (TEAMID)" 证书
#      （Xcode → Settings → Accounts → 下载，或 developer.apple.com 手动下载 .cer 双击）
#   2) 存好公证凭据（二选一）：
#      a) App-specific 密码方式：
#         xcrun notarytool store-credentials "AC_PASSWORD" \
#            --apple-id "you@icloud.com" --team-id TEAMID --password "app-specific-pwd"
#      b) App Store Connect API Key 方式（更稳，CI 友好）：
#         把 AuthKey_XXXX.p8 放好，提交时改用
#         --key /path/AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
#
# 用法：
#   export DEV_ID="Developer ID Application: Your Name (TEAMID)"
#   export NOTARY_PROFILE="AC_PASSWORD"        # 对应 store-credentials 起的名
#   bash notarize.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/PortWatcher.app"
ZIP="PortWatcher.zip"

# 从环境变量读，不要把证书/Team 写死在脚本里
DEV_ID="${DEV_ID:-Developer ID Application: YOUR_TEAM_NAME (TEAMID)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

test -d "$APP" || { echo "找不到 $APP：先跑 swift build -c release --disable-sandbox 并装配 .app"; exit 1; }

echo "==> 1) 签名（hardened runtime，不开启 App Sandbox，保留 lsof/ps/launchctl 能力）"
codesign --deep --force --options runtime --timestamp \
  --sign "$DEV_ID" "$APP"

echo "==> 2) 打包 zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 3) 提交公证并等待"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> 4) 盖章（stapler），让 app 自带公证票据，离线也不报警"
xcrun stapler staple "$APP"

echo "==> 完成：$APP 已签名并公证，可直接分发（.zip 或再打成 .dmg）"
