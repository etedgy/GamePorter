---
name: gameporter
description: "GamePorter — yan's own native macOS Windows-game launcher (Whisky/CrossOver replacement) built on Apple GPTK D3DMetal; repo ~/GamePorter, installed /Applications/GamePorter.app"
metadata: 
  node_type: memory
  type: project
  originSessionId: 22b83917-f49a-48b7-afd3-2c6b4396baad
---

GamePorter (created 2026-07-06): personal-use native SwiftUI app replacing CrossOver/Whisky. Repo `~/GamePorter` → private GitHub `etedgy/GamePorter`, `./build.sh` → /Applications/GamePorter.app (ad-hoc signed).

- Runtime: `~/Library/Application Support/GamePorter/` — `Toolkit/` holds the Gcenx game-porting-toolkit 3.0-3 build (x86_64 Wine + Apple D3DMetal.framework, runs under Rosetta; wine at `Toolkit/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64`), `Bottles/<uuid>/` = Wine prefixes + `gameporter.json`, `Logs/`.
- App auto-downloads the toolkit from Gcenx GitHub releases if missing; SetupView also imports Apple's official GPTK dmg (redist/lib overlay) to upgrade D3DMetal — user has an Apple dev account.
- Features: bottles (win10 default), run exe (`wine64 start /unix`), .msi via msiexec, one-click Steam installer, program auto-discovery + pinning, toggles ESYNC / MTL_HUD_ENABLED / RetinaMode registry / ROSETTA_ADVERTISE_AVX, tools (winecfg/taskmgr/regedit/uninstaller), wineserver -k kill, uninstall (PR #1: parses system.reg Uninstall keys; QuietUninstallString → `msiexec /x{GUID} /qn` → cmd /c UninstallString → uninstaller --remove).
- Gotcha learned live: MSI UI dialogs (even /qb) fail to render under this Wine build and hang invisibly — always use /qn for msiexec; wine GUI processes inherit com.yan.gameporter bundle id.
- Verified end-to-end 2026-07-06: bottle created via UI, winecfg launched. Known quirk: first Create click in the NewBottleSheet sometimes needs a second click.
- CrossOver.app also installed on this Mac (separate, unrelated).
- Researched roadmap (2026-07-06, user approved direction, not yet built): bottle bootstrap (vc_redist silent + corefonts + CurrentBuild=19042 spoof), winetricks panel, DXVK-macOS v1.10.3-async toggle (Gcenx builtin tarball, matches our CX22 wine ABI; covers DX9/10 which otherwise hit slow WineD3D/OpenGL), per-game .app shortcuts, Fix-Steam button (steam.cfg BootStrapperInhibitAll + launch args), D3DM shader-cache clear (`$(getconf DARWIN_USER_CACHE_DIR)/d3dm`), bottle snapshots, env-var/launch-args editors. Our wine = esync only (msync tested, unsupported); DXMT needs newer wine ABI — experimental/later.
- This memory file lives in-repo at `memory/gameporter.md`, symlinked from `~/.claude/projects/-Users-yan/memory/gameporter.md`; commit+push after memory updates.

Related: [[aiscope]] [[local-coder-stack]]
