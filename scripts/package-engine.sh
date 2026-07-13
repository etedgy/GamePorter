#!/bin/bash
# Package the self-built "GamePorter Wine" engine as a FREE, redistributable tarball.
#
# Ships: our from-source Wine 11 (wow64) + free libs (MoltenVK / gnutls / gmp) + Wine's own
# VKD3D d3d12/dxgi. Does NOT ship any Apple-GPTK / CrossOver proprietary files — D3DMetal
# and libd3dshared are staged at runtime from the user's own installed Game Porting Toolkit
# (see EngineManager.stageD3DMetal). Without GPTK the engine still runs games via VKD3D.
#
#   scripts/package-engine.sh [version]     # default version 1.0
# Output: build/releases/gpwine-<version>.tar.gz  → upload to the GitHub release the
# EngineCatalogEntry("gpwine") URL points at.
set -euo pipefail
cd "$(dirname "$0")/.."

VER="${1:-1.0}"
INST="${GPWINE_INST:-$HOME/wine-build/inst}"
BUILD64="${GPWINE_BUILD64:-$HOME/wine-build/build64}"
OUT="build/releases"; mkdir -p "$OUT"
STAGE="build/gpwine-pkg"

[ -x "$INST/bin/wine" ] || { echo "no wine at $INST/bin/wine (set GPWINE_INST)"; exit 1; }

rm -rf "$STAGE"; mkdir -p "$STAGE"
/usr/bin/ditto "$INST" "$STAGE"

U="$STAGE/lib/wine/x86_64-unix"; W="$STAGE/lib/wine/x86_64-windows"

# 1. Strip proprietary Apple-GPTK / CrossOver files (staged from the user's GPTK at runtime).
rm -rf "$U/D3DMetal.framework"
rm -f  "$U/libd3dshared.dylib" "$U/d3d12.so" "$U/dxgi.so"

# 2. Restore Wine's own free VKD3D d3d12/dxgi (the D3DMetal glue replaced them in the dev tree).
cp -f "$BUILD64/dlls/d3d12/x86_64-windows/d3d12.dll" "$W/d3d12.dll"
cp -f "$BUILD64/dlls/dxgi/x86_64-windows/dxgi.dll"   "$W/dxgi.dll"

# 3. Drop any leftover dev backups.
find "$STAGE" -type f \( -name '*.cx' -o -name '*.gptk' -o -name '*.vkd3d' -o -name '*.gcc16' \
    -o -name '*.clang16' -o -name '*.clang21' -o -name '*.ours' -o -name '*.ours1015' \) -delete

# 4. Sanity: nothing proprietary left.
if find "$STAGE" \( -name 'D3DMetal*' -o -name 'libd3dshared*' \) | grep -q .; then
    echo "ERROR: proprietary files still present in package"; exit 1
fi
echo "free engine staged ($(du -sh "$STAGE" | cut -f1)):"
ls "$W/d3d12.dll" "$U/libMoltenVK.dylib" "$U/libgnutls.30.dylib" >/dev/null && echo "  essentials OK"

# 5. Tarball (contents at top → extracts into Engines/gpwine/{bin,lib,...}).
TAR="$OUT/gpwine-$VER.tar.gz"
rm -f "$TAR"
tar -C "$STAGE" -czf "$TAR" .
rm -rf "$STAGE"
echo "packaged: $TAR  ($(du -h "$TAR" | cut -f1))"
echo "upload as the EngineCatalogEntry(\"gpwine\") release asset."
