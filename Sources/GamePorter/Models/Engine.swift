import Foundation

/// A graphics translation layer, selectable per bottle.
enum RendererKind: String, Codable, CaseIterable, Identifiable {
    case d3dmetal   // DX11/12 → Metal (Apple's Game Porting Toolkit)
    case dxmt       // DX10/11 → Metal (3Shain/dxmt, needs Wine 10.18+)
    case dxvk       // DX9/10/11 → Vulkan via MoltenVK
    case wined3d    // DX → OpenGL, Wine's built-in (max compatibility, slower)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .d3dmetal: return "D3DMetal — DirectX 11/12 → Metal (Apple)"
        case .dxmt:     return "DXMT — DirectX 10/11 → Metal"
        case .dxvk:     return "DXVK — DirectX 9/10/11 → Vulkan (Metal)"
        case .wined3d:  return "WineD3D — DirectX → OpenGL (compatibility)"
        }
    }

    var blurb: String {
        switch self {
        case .d3dmetal: return "Best for modern DX11/DX12 games. Apple's own layer."
        case .dxmt:     return "Newer DX10/11 path, often faster than D3DMetal on Apple Silicon."
        case .dxvk:     return "DX9–11 → Metal via our patched DXVK. Best for older games; full shaders."
        case .wined3d:  return "Universal fallback when nothing else renders."
        }
    }
}

/// A Wine runtime installed on disk. GamePorter can hold several.
struct Engine: Identifiable, Hashable {
    let id: String            // stable key & folder name, e.g. "wine-staging-11.10"
    let name: String          // display name
    let wineBin: URL          // path to the wine loader ("wine", "wine64", or "wineloader")
    let kind: Kind
    var extraEnv: [String: String] = [:]   // engine-specific env (CrossOver loader paths)

    enum Kind: String { case gptk, vanilla, crossover }

    var wineserver: URL { wineBin.deletingLastPathComponent().appendingPathComponent("wineserver") }
    /// …/Resources/wine — lib/external holds D3DMetal on GPTK builds.
    var wineRoot: URL { wineBin.deletingLastPathComponent().deletingLastPathComponent() }

    /// Renderers this engine can drive.
    var supportedRenderers: [RendererKind] {
        switch kind {
        case .gptk:      return [.d3dmetal, .dxvk, .wined3d]   // old Wine, has Apple D3DMetal
        case .vanilla:   return [.dxmt, .dxvk, .wined3d]       // Wine 11, no D3DMetal, gets DXMT
        case .crossover: return [.d3dmetal, .dxvk, .wined3d]   // your CrossOver: D3DMetal + proper 32-bit
        }
    }

    var defaultRenderer: RendererKind { kind == .vanilla ? .dxmt : .d3dmetal }

    var versionNote: String {
        switch kind {
        case .gptk:      return "older Wine, Apple D3DMetal"
        case .vanilla:   return "modern Wine, best installer compatibility"
        case .crossover: return "your installed CrossOver — installs stubborn 32-bit games"
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
            id: "wine-staging-11.10",
            name: "Wine Staging 11.10",
            kind: .vanilla,
            url: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.10/wine-staging-11.10-osx64.tar.xz")!,
            sizeMB: 190,
            summary: "Modern Wine (2026). Installs repack/compressed installers that old Wine can't. Use with DXMT or DXVK."),
        EngineCatalogEntry(
            id: "gptk-3.0-3",
            name: "Game Porting Toolkit 3.0-3",
            kind: .gptk,
            url: URL(string: "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz")!,
            sizeMB: 240,
            summary: "Apple's D3DMetal layer for DX11/DX12. Older Wine base."),
    ]
}
