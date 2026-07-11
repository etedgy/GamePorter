# Third-Party Notices

GamePorter bundles and/or builds upon the following third-party components.

## DXVK (bundled binaries in `Resources/dxvk/`)

The Direct3D 9/10/11 → Vulkan translation libraries in `Resources/dxvk/` are a
patched build of DXVK for Apple Silicon (Metal via MoltenVK). They are derived
from:

- **DXVK** — https://github.com/doitsujin/dxvk
- **DXVK-macOS** (Apple Silicon fork) — https://github.com/Gcenx/DXVK-macOS

GamePorter's patch enables the Direct3D 9 path on Apple Silicon (gates
`geometryShader` / cull-distance on device support so Metal, which lacks them,
is not rejected). See `patches/` for the diff.

DXVK is distributed under the **zlib/libpng license**:

```
Copyright (c) 2017 Philip Rebohle
Copyright (c) 2019 Joshua Ashton

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.

3. This notice may not be removed or altered from any source distribution.
```

## Wine / Game Porting Toolkit / CrossOver / DXMT

GamePorter drives, but does not bundle, external Wine-based runtimes
(Apple's Game Porting Toolkit, Gcenx's Wine builds, a user-supplied CrossOver
install) and the DXMT renderer. Each is downloaded/used under its own license.
