import SwiftUI
import AppKit

/// CrossOver-style launcher: installed games as a grid of tiles, each with the
/// real icon pulled from its .exe and its name. Click a tile to play.
struct GameLauncherGrid: View {
    let games: [DiscoveredProgram]
    let disabled: Bool
    let launch: (DiscoveredProgram) -> Void

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 148), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(games) { game in
                GameTile(game: game, action: { launch(game) })
                    .disabled(disabled)
            }
        }
        .padding(.vertical, 6)
    }
}

/// One game tile: extracted icon (async, cached) + name, with a hover affordance.
private struct GameTile: View {
    let game: DiscoveredProgram
    let action: () -> Void
    @State private var icon: NSImage?
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                iconWell
                Text(game.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .frame(width: 108, height: 30, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Play \(game.name)")
        .task(id: game.unixPath) { await loadIcon() }
    }

    private var iconWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(hovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable().interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [.teal, .indigo],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 60, height: 60)
                        .overlay(Image(systemName: "gamecontroller.fill")
                            .font(.title2).foregroundStyle(.white))
                }
            }
            .shadow(color: .black.opacity(0.18), radius: hovering ? 6 : 3, y: 2)
        }
        .frame(width: 84, height: 84)
        .overlay(alignment: .center) {
            if hovering {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, .teal)
                    .shadow(radius: 3)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func loadIcon() async {
        let path = game.unixPath
        let img = await Task.detached(priority: .utility) {
            IconExtractor.icon(forExe: path)
        }.value
        await MainActor.run { self.icon = img }
    }
}
