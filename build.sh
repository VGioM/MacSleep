#!/bin/bash
# Builds MacSleep.app into ./dist and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="dist/MacSleep.app"

echo "▸ Compilation ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MacSleep"

echo "▸ Assemblage du bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacSleep"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>MacSleep</string>
    <key>CFBundleDisplayName</key>           <string>MacSleep</string>
    <key>CFBundleExecutable</key>            <string>MacSleep</string>
    <key>CFBundleIdentifier</key>            <string>com.macsleep.app</string>
    <key>CFBundleVersion</key>               <string>1.0</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>LSApplicationCategoryType</key>     <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSHumanReadableCopyright</key>      <string>MacSleep</string>
</dict>
</plist>
PLIST

echo "▸ Signature…"
codesign --force --sign - "$APP" 2>/dev/null

echo "✓ $APP prêt"
