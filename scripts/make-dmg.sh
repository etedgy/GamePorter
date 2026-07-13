#!/bin/bash
# Build a drag-to-Applications DMG installer for GamePorter.
#   scripts/make-dmg.sh [version]      # default: version from Info.plist
# Output: build/releases/GamePorter-<ver>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

# Ensure the app is built.
[ -d build/GamePorter.app ] || ./build.sh
VER="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"

OUT="build/releases"; mkdir -p "$OUT"
DMG="$OUT/GamePorter-$VER.dmg"
STAGE="$(mktemp -d)/GamePorter"
mkdir -p "$STAGE"

# Lay out the DMG contents: the app + a symlink to /Applications so users drag across.
cp -R build/GamePorter.app "$STAGE/GamePorter.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "GamePorter $VER" -srcfolder "$STAGE" -ov -format UDZO \
    -fs HFS+ "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"

# Ad-hoc sign the DMG (a real Developer ID cert + notarization is still recommended — see RELEASING.md).
codesign --force --sign - "$DMG" 2>/dev/null || true

echo "built: $DMG ($(du -h "$DMG" | cut -f1))"
echo "Drag-to-Applications installer. NOTE: ad-hoc signed → Gatekeeper will quarantine downloads."
echo "For a clean install experience, notarize with a Developer ID cert (see RELEASING.md)."
