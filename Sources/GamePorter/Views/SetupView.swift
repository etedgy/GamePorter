import SwiftUI

struct SetupView: View {
    @EnvironmentObject var toolkit: ToolkitManager
    @State private var showDMGPicker = false
    @State private var importResult: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 56))
                .foregroundStyle(.teal)
            Text("Set up the Game Porting Toolkit")
                .font(.title.bold())
            Text("GamePorter needs the Wine runtime with Apple's D3DMetal\n(DirectX 11/12 → Metal). One-time download, ~240 MB.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            switch toolkit.status {
            case .missing:
                Button {
                    toolkit.install()
                } label: {
                    Label("Download & Install", systemImage: "arrow.down.circle.fill")
                        .font(.title3)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .downloading(let progress):
                ProgressView(value: progress) {
                    Text("Downloading toolkit… \(Int(progress * 100))%")
                }
                .frame(width: 320)

            case .extracting:
                ProgressView { Text("Extracting…") }

            case .failed(let message):
                VStack(spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Button("Retry") { toolkit.install() }
                }

            case .installed:
                Label("Toolkit installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $showDMGPicker,
                      allowedContentTypes: [.diskImage]) { result in
            if case .success(let url) = result {
                Task {
                    do {
                        try await toolkit.importAppleGPTK(dmg: url)
                        importResult = "D3DMetal upgraded from Apple GPTK dmg."
                    } catch {
                        importResult = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                if let importResult {
                    Text(importResult).font(.caption).foregroundStyle(.secondary)
                }
                Button("Upgrade D3DMetal from an Apple GPTK .dmg…") {
                    showDMGPicker = true
                }
                .buttonStyle(.link)
                .font(.caption)
                Text("Download the official dmg from developer.apple.com → Game Porting Toolkit")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.bottom, 12)
        }
    }
}
