#!/bin/bash
# Rebuild our patched VKD3D-Proton (DX12→Vulkan) and stage into the app.
set -e
VK="$HOME/vkd3d-proton"; P="$HOME/GamePorter/patches"
cd "$VK"
git apply --check "$P/vkd3d-moltenvk-optional-procs.patch" 2>/dev/null && git apply "$P/vkd3d-moltenvk-optional-procs.patch" || echo "vkd3d patch already applied"
[ -d build.64 ] || meson setup --cross-file build-win64.txt --buildtype release -Denable_tests=false build.64
ninja -C build.64
cp build.64/libs/d3d12/d3d12.dll     "$HOME/GamePorter/Resources/vkd3d/x64/"
cp build.64/libs/d3d12core/d3d12core.dll "$HOME/GamePorter/Resources/vkd3d/x64/"
echo "VKD3D built + staged."
