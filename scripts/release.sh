#!/bin/bash
# Cut a GamePorter release: build the app, zip it, and (re)generate the Sparkle appcast.
#
# One-time setup (do this once, ever):
#   1. Generate the Sparkle signing keypair:
#        .build/artifacts/sparkle/Sparkle/bin/generate_keys
#      It stores the PRIVATE key in your login Keychain and prints the PUBLIC key.
#   2. Paste that public key into Resources/Info.plist under SUPublicEDKey.
#
# Each release:
#   scripts/release.sh 1.1        # version = CFBundleShortVersionString
#
# Then upload BOTH build/releases/GamePorter-<ver>.zip and build/releases/appcast.xml
# as assets on the GitHub release the SUFeedURL points at
# (https://github.com/etedgy/GamePorter/releases). Sparkle clients poll that appcast.
set -euo pipefail
cd "$(dirname "$0")/.."

VER="${1:?usage: release.sh <version>  e.g. release.sh 1.1}"
BIN=.build/artifacts/sparkle/Sparkle/bin
REL=build/releases
mkdir -p "$REL"

# Stamp the version into Info.plist (marketing + build number both = VER for simplicity).
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VER"            Resources/Info.plist

# Build the signed .app (embeds Sparkle.framework).
./build.sh

# Zip the app for distribution (ditto preserves symlinks/frameworks/signatures).
ZIP="$REL/GamePorter-$VER.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent build/GamePorter.app "$ZIP"

# Regenerate the appcast from every zip in the releases dir. generate_appcast signs each
# with the private key from the Keychain and writes appcast.xml with the EdDSA signatures.
"$BIN/generate_appcast" "$REL"

echo ""
echo "Release $VER built:"
echo "  $ZIP"
echo "  $REL/appcast.xml"
echo ""
echo "Upload BOTH to the GitHub release (tag them so the SUFeedURL resolves):"
echo "  gh release create v$VER \"$ZIP\" \"$REL/appcast.xml\" -t \"GamePorter $VER\" -n \"...\""
echo "  # or: gh release upload v$VER \"$ZIP\" \"$REL/appcast.xml\" --clobber"
