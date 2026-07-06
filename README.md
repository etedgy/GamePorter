# GamePorter

Personal native macOS app for installing and running Windows games via Apple's
Game Porting Toolkit (D3DMetal). My own CrossOver/Whisky — no subscription.

**Personal use only.** D3DMetal is Apple-proprietary (license in the toolkit
download); the Wine build is the Gcenx GPTK evaluation environment.

## How it works

- SwiftUI app (`Sources/GamePorter`), no external dependencies.
- Runtime lives in `~/Library/Application Support/GamePorter/`:
  - `Toolkit/` — Gcenx Game Porting Toolkit build (x86_64 Wine + Apple
    D3DMetal.framework), auto-downloaded by the app on first run if missing.
  - `Bottles/<uuid>/` — one Wine prefix per bottle + `gameporter.json` metadata.
  - `Logs/` — per-launch wine output.
- Wine binaries are x86_64; Rosetta 2 runs them transparently on Apple Silicon.
  D3DMetal translates DirectX 11/12 → Metal.

## Features

- Bottles: create (win10/win11/win7/winxp64), delete, open C: in Finder, kill all.
- Run any `.exe`, install apps (`.exe`/`.msi`), one-click Steam install.
- Program auto-discovery in Program Files + pinning favorites.
- Per-bottle toggles: ESYNC, Metal HUD (FPS overlay), Retina mode,
  AVX passthrough (`ROSETTA_ADVERTISE_AVX=1` — helps games that require AVX).
- Tools menu: winecfg, taskmgr, regedit, command prompt.
- Upgrade path: import Apple's official GPTK `.dmg` (developer.apple.com) to
  overlay a newer D3DMetal onto the toolkit (Setup screen → bottom link).

## Build

```bash
./build.sh   # swift build + bundle + ad-hoc codesign + install to /Applications
```

## Tips

- One bottle per game/launcher keeps things debuggable.
- Steam: toggle "Advertise AVX" on (default); if Steam webview is black, try
  adding `-noverifyfiles -nobootstrapupdate -skipinitialbootstrap -norepairfiles`
  launch args to a pinned Steam entry.
- DX9/DX10 games use Wine's builtin translation (slower); D3DMetal shines on
  DX11/DX12 titles.
- Check `Logs/` when a game won't start.
