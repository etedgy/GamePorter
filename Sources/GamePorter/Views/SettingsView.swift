import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var engines: EngineManager
    @Environment(\.dismiss) private var dismiss

    private var s: Binding<AppSettings> { $settingsManager.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            GroupBox("Performance") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Frame-rate limit", selection: s.fpsCap) {
                        Text("Unlimited").tag(0)
                        Text("30 FPS").tag(30)
                        Text("60 FPS").tag(60)
                        Text("120 FPS").tag(120)
                        Text("144 FPS").tag(144)
                    }
                    Text("Caps every game to save power/heat. Works with the DXVK and DXMT renderers; for D3DMetal or WineD3D use the game's own V-Sync.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Toggle("Show FPS overlay on all games", isOn: s.showFPSOverlay)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Defaults for new bottles") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("ESYNC (faster synchronization)", isOn: s.esyncDefault)
                    Toggle("Advertise AVX to games (Rosetta)", isOn: s.advertiseAVXDefault)
                    if !engines.engines.isEmpty {
                        Picker("Engine", selection: Binding(
                            get: { settingsManager.settings.defaultEngineID ?? engines.engines.first?.id ?? "" },
                            set: { settingsManager.settings.defaultEngineID = $0 })) {
                            ForEach(engines.engines) { e in Text(e.name).tag(e.id) }
                        }
                    }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 460, height: 420)
    }
}
