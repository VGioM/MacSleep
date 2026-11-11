#!/bin/bash
# Builds MacSleep.app into ./dist and signs it.
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
    <key>CFBundleVersion</key>               <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>    <string>1.0.0</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>LSApplicationCategoryType</key>     <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSHumanReadableCopyright</key>      <string>MacSleep</string>
</dict>
</plist>
PLIST

# The debug map names every source file by its absolute path on this Mac;
# a release build has no use for it.
[ "$CONFIG" = "release" ] && strip -S "$APP/Contents/MacOS/MacSleep" 2>/dev/null

# Signed with the local certificate when there is one (./signing-cert.sh makes
# it): the in-app updater only installs a new version signed like the running
# one. Ad hoc otherwise.
IDENTITY="-"
if security find-identity -p codesigning 2>/dev/null | grep -q "VGioM Local Signing"; then
    IDENTITY="VGioM Local Signing"
fi
if [ "$IDENTITY" = "-" ]; then
    echo "▸ Signature (ad hoc : ./signing-cert.sh crée le certificat local)…"
else
    echo "▸ Signature ($IDENTITY)…"
fi
codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null

echo "✓ $APP prêt"
