import Foundation

/// A graphics translation layer, selectable per bottle.
enum RendererKind: String, Codable, CaseIterable, Identifiable {
    case d3dmetal   // DX11/12 → Metal (Apple's Game Porting Toolkit)
    case dxmt       // DX10/11 → Metal (3Shain/dxmt, needs Wine 10.18+)
    case dxvk       // DX9/10/11 → Vulkan via MoltenVK
    case vkd3d      // DX12 → Vulkan via MoltenVK (our patched VKD3D-Proton + MoltenVK)
    case wined3d    // DX → OpenGL, Wine's built-in (max compatibility, slower)
    case builtin    // Wine's own DLLs untouched: d3d12 → Wine's built-in VKD3D → Vulkan → MoltenVK

    var id: String { rawValue }

    var label: String {
        switch self {
        case .d3dmetal: return "D3DMetal — DirectX 11/12 → Metal (Apple)"
        case .dxmt:     return "DXMT — DirectX 10/11 → Metal"
        case .dxvk:     return "DXVK — DirectX 9/10/11 → Vulkan (Metal)"
        case .vkd3d:    return "VKD3D — DirectX 12 → Vulkan (Metal)"
        case .wined3d:  return "WineD3D — DirectX → OpenGL (compatibility)"
        case .builtin:  return "Built-in — DirectX 12 → Metal (Apple D3DMetal)"
        }
    }

    var blurb: String {
        switch self {
        case .d3dmetal: return "Best for modern DX11/DX12 games. Apple's own layer."
        case .dxmt:     return "Newer DX10/11 path, often faster than D3DMetal on Apple Silicon."
        case .dxvk:     return "DX9–11 → Metal via our patched DXVK. Best for older games; full shaders."
        case .vkd3d:    return "DX12 → Metal via our patched VKD3D-Proton + MoltenVK. For modern DX12 games (needs the WhiskyWine engine)."
        case .wined3d:  return "Universal fallback when nothing else renders."
        case .builtin:  return "DirectX 12 → Metal via Apple's D3DMetal — correct, fast 3D for modern DX12 games. The recommended path on the self-built engine."
        }
    }
}

/// A Wine runtime installed on disk. GamePorter can hold several.
struct Engine: Identifiable, Hashable {
    let id: String            // stable key & folder name, e.g. "wine-staging-11.10"
    let name: String          // display name
    let wineBin: URL          // path to the wine loader ("wine", "wine64", or "wineloader")
    let kind: Kind
    var extraEnv: [String: String] = [:]   // engine-specific env (loader paths, etc.)

    enum Kind: String { case gptk, vanilla, gpwine }

    var wineserver: URL { wineBin.deletingLastPathComponent().appendingPathComponent("wineserver") }
    /// …/Resources/wine — lib/external holds D3DMetal on GPTK builds.
    var wineRoot: URL { wineBin.deletingLastPathComponent().deletingLastPathComponent() }

    /// Renderers this engine can drive.
    var supportedRenderers: [RendererKind] {
        switch kind {
        case .gptk:      return [.d3dmetal, .dxvk, .wined3d]   // old Wine, has Apple D3DMetal
        case .vanilla:   return [.vkd3d, .dxmt, .dxvk, .wined3d]  // Wine 11 + our MoltenVK: DX12 via VKD3D, plus DXMT/DXVK
        case .gpwine:    return [.builtin, .vkd3d, .dxvk, .wined3d]  // self-built Wine 11: D3DMetal (builtin) + MoltenVK
        }
    }

    var defaultRenderer: RendererKind {
        switch kind {
        case .vanilla: return .dxmt
        case .gpwine:  return .builtin   // D3DMetal — the recommended DX12 path
        default:       return .d3dmetal
        }
    }

    var versionNote: String {
        switch kind {
        case .gptk:      return "older Wine, Apple D3DMetal"
        case .vanilla:   return "modern Wine, best installer compatibility"
        case .gpwine:    return "self-built Wine 11 — Metal rendering, runs the widest range of games"
        }
    }
}

/// An engine GamePorter knows how to download and install.
struct EngineCatalogEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: Engine.Kind
    let url: URL
    let sizeMB: Int
    let summary: String

    static let all: [EngineCatalogEntry] = [
        EngineCatalogEntry(
            id: "gpwine",
            name: "GamePorter Wine (self-built)",
            kind: .gpwine,
            url: URL(string: "https://github.com/etedgy/GamePorter/releases/download/engine-gpwine-1.0/gpwine-1.0.tar.gz")!,
            sizeMB: 465,
            summary: "Our own from-source Wine 11 (wow64) with Apple D3DMetal rendering (auto-installed) and fast-sync online login. Runs the widest range of modern DX12 games."),
        EngineCatalogEntry(
            id: "wine-staging-11.10",
            name: "Wine Staging 11.10",
            kind: .vanilla,
            url: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.10/wine-staging-11.10-osx64.tar.xz")!,
            sizeMB: 190,
            summary: "Modern Wine (2026). Installs compressed installers that old Wine can't. Use with DXMT or DXVK."),
        EngineCatalogEntry(
            id: "gptk-3.0-3",
            name: "Game Porting Toolkit 3.0-3",
            kind: .gptk,
            url: URL(string: "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz")!,
            sizeMB: 240,
            summary: "Apple's D3DMetal layer for DX11/DX12. Older Wine base."),
    ]
}
