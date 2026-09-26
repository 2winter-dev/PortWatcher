#!/usr/bin/env bash
# 构建 PortWatcher 为独立的 .app（菜单栏常驻，无 Dock 图标）
set -euo pipefail
cd "$(dirname "$0")"

echo "==> swift build (release)"
swift build -c release
BIN=".build/release/PortWatcher"
test -f "$BIN" || { echo "构建失败：找不到 $BIN"; exit 1; }

APP="build/PortWatcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/PortWatcher"

# App 图标 + 顶栏模板图（由 AppStore/ 下的 SVG 渲染产出）
ICNS="AppStore/icon/PortWatcher.icns"
MENUBAR="AppStore/menubar/template.png"
test -f "$ICNS" || { echo "缺少 $ICNS，先按 AppStore/README 说明渲染"; exit 1; }
test -f "$MENUBAR" || { echo "缺少 $MENUBAR，先按 AppStore/README 说明渲染"; exit 1; }
cp "$ICNS" "$APP/Contents/Resources/PortWatcher.icns"
cp "$MENUBAR" "$APP/Contents/Resources/menubar.png"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PortWatcher</string>
    <key>CFBundleDisplayName</key><string>PortWatcher</string>
    <key>CFBundleIdentifier</key><string>com.bbcat.PortWatcher</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>PortWatcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>PortWatcher</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

echo "==> 已生成: $APP"
echo "    运行: open build/PortWatcher.app"
echo "    建议放到 /Applications 以启用「登录时启动」"
