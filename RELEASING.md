# Releasing GamePorter

Two things get shipped, both hosted on **GitHub Releases** under `etedgy/GamePorter`:

1. **The app** (auto-updates via Sparkle) — `GamePorter-<ver>.zip` + `appcast.xml`.
2. **The self-built Wine engine** (downloaded on demand) — `gpwine-<ver>.tar.gz`.

Everything shipped is free/redistributable. **Never** commit or host Apple-GPTK / CrossOver
files (`D3DMetal.framework`, `libd3dshared.dylib`, the D3DMetal `d3d12.dll` glue) — they're
Apple's proprietary Game Porting Toolkit and are staged at runtime from the *user's own* GPTK
install (`EngineManager.stageD3DMetal`). `scripts/package-engine.sh` strips them and verifies.

## One-time: auto-update signing key

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

Stores the **private** key in your login Keychain, prints the **public** key. Paste the public
key into `Resources/Info.plist` → `SUPublicEDKey` (replacing `REPLACE_WITH_SPARKLE_ED_PUBLIC_KEY`).
Back up the private key (`generate_keys -x private_key.pem`) somewhere safe — lose it and you
can't ship signed updates.

## Cut an app release

```sh
scripts/release.sh 1.1
# builds build/GamePorter.app, zips it, regenerates build/releases/appcast.xml (signed)
gh release create v1.1 build/releases/GamePorter-1.1.zip build/releases/appcast.xml \
   -t "GamePorter 1.1" -n "Release notes…"
```

Sparkle clients poll `SUFeedURL`
(`https://github.com/etedgy/GamePorter/releases/latest/download/appcast.xml`) once a day and on
"Check for Updates…" (GamePorter menu → app menu). Keep every past `.zip` in `build/releases/`
so `generate_appcast` can build deltas.

## Publish the Wine engine

The engine tarball is large (~465 MB) and only changes when the Wine build changes.

```sh
scripts/package-engine.sh 1.0        # → build/releases/gpwine-1.0.tar.gz (free bits only)
gh release create engine-gpwine-1.0 build/releases/gpwine-1.0.tar.gz \
   -t "GamePorter Wine 1.0" -n "Self-built Wine engine"
```

The tag/filename must match `EngineCatalogEntry("gpwine")` in `Sources/GamePorter/Models/Engine.swift`.

**Mark engine releases as pre-release** (`gh release edit <tag> --prerelease`) so they never become
"latest" — the Sparkle feed lives on the newest *app* release (`releases/latest/download/appcast.xml`).
If you rebuild the engine, bump both the tag and that catalog entry (id/url/sizeMB).

## Apple Game Porting Toolkit (auto-installed)

D2R's D3DMetal rendering + anti-tamper storm-fix come from Apple's GPTK. GamePorter pulls it
automatically (`EngineManager.ensureAppleGPTK` → the `gptk` catalog entry, redistributed by
Gcenx) when the self-built engine is present. Users don't need CrossOver.
