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
DEV_ID="${DEV_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

# --- 前置校验：证书必须显式设置且真实存在于钥匙串 ---
if [[ -z "$DEV_ID" || "$DEV_ID" == *"YOUR_TEAM_NAME"* ]]; then
  echo "✗ 未设置 DEV_ID（或仍是占位符）。" >&2
  echo "  先在钥匙串装好 \"Developer ID Application: <你的名字> (TEAMID)\" 证书，然后：" >&2
  echo "    export DEV_ID=\"Developer ID Application: 你的名字 (TEAMID)\"" >&2
  exit 1
fi

# 校验钥匙串里确有该证书
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$DEV_ID"; then
  echo "✗ 钥匙串里找不到名为 '$DEV_ID' 的证书。" >&2
  echo "  当前可用的代码签名证书：" >&2
  security find-identity -v -p codesigning 2>/dev/null | sed 's/^/    /' >&2 || true
  echo "  必须且只能是 \"Developer ID Application: ...\" 证书（不是 Apple Development）。" >&2
  echo "  Apple Development 证书无法用于公证/对外分发，Gatekeeper 会在别的机器上拦截。" >&2
  echo "  获取方式：developer.apple.com → Certificates → + → Developer ID Application" >&2
  echo "           → 生成 CSR → 下载 .cer → 双击装入登录钥匙串。" >&2
  exit 1
fi

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
