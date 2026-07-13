#!/bin/bash
# Build GamePorter.app and install it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64

APP="build/GamePorter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/arm64-apple-macosx/release/GamePorter "$APP/Contents/MacOS/GamePorter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Our patched DXVK (d3d9-capable, Apple-Silicon-safe) — bundled so the DXVK renderer works offline.
[ -d Resources/dxvk ] && cp -R Resources/dxvk "$APP/Contents/Resources/dxvk"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Embed Sparkle.framework (auto-updater). It carries its own XPC services + Autoupdate/Updater;
# it must live in Contents/Frameworks and the executable needs an rpath to find it.
SPARKLE_FW=$(/usr/bin/find .build/artifacts -type d -name 'Sparkle.framework' -path '*macos*' | head -1)
if [ -n "${SPARKLE_FW:-}" ]; then
    cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/GamePorter" 2>/dev/null || true
    # Sign the framework's nested code first (XPC services / helpers), then the framework.
    codesign --force --sign - --timestamp=none --deep "$APP/Contents/Frameworks/Sparkle.framework"
else
    echo "WARNING: Sparkle.framework not found — auto-update will not work. Run 'swift package resolve'." >&2
fi

# Sign the whole app last (inside-out).
codesign --force --deep --sign - "$APP"

rm -rf /Applications/GamePorter.app
cp -R "$APP" /Applications/GamePorter.app
echo "Installed: /Applications/GamePorter.app"
