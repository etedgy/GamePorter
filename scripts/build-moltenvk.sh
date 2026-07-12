#!/bin/bash
# Rebuild our patched MoltenVK (SPIRV-Cross MSL fixes) and swap into the WhiskyWine engine.
set -e
MVK="$HOME/MoltenVK"; P="$HOME/GamePorter/patches"
cd "$MVK/External/SPIRV-Cross"
git apply --check "$P/spirv-cross-bda-atomic-vector.patch" 2>/dev/null && git apply "$P/spirv-cross-bda-atomic-vector.patch" || echo "spirv-cross patch already applied"
git rev-parse HEAD > /dev/null && git add -A && git commit -q -m "GamePorter SPIRV-Cross patches" 2>/dev/null || true
cd "$MVK"
echo -n "$(cd External/SPIRV-Cross && git rev-parse HEAD)" > ExternalRevisions/SPIRV-Cross_repo_revision
./fetchDependencies --macos
rm -f Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib
xcodebuild -project MoltenVKPackaging.xcodeproj -scheme "MoltenVK Package (macOS only)" -configuration Release clean -quiet
make macos
cp Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib \
   "$HOME/Library/Application Support/GamePorter/Engines/whiskywine-11/wine/lib/libMoltenVK.dylib"
echo "MoltenVK built + swapped."
