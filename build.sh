#!/bin/bash
# Build GamePorter.app and install it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64

APP="build/GamePorter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/GamePorter "$APP/Contents/MacOS/GamePorter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --sign - "$APP"

rm -rf /Applications/GamePorter.app
cp -R "$APP" /Applications/GamePorter.app
echo "Installed: /Applications/GamePorter.app"
