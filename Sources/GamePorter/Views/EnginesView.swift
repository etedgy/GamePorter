import SwiftUI

struct EnginesView: View {
    @EnvironmentObject var engines: EngineManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Engines").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("Wine runtimes GamePorter can run bottles on. Install more than one and pick per bottle.")
                .font(.caption).foregroundStyle(.secondary)

            GroupBox("Installed") {
                if engines.engines.isEmpty {
                    Text("None yet — install one below.")
                        .foregroundStyle(.secondary).padding(8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(engines.engines) { e in
                            HStack {
                                Image(systemName: e.kind == .gptk ? "sparkles" : "bolt.fill")
                                    .foregroundStyle(e.kind == .gptk ? .purple : .teal)
                                VStack(alignment: .leading) {
                                    Text(e.name)
                                    Text(e.versionNote).font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(e.supportedRenderers.map { $0.rawValue.uppercased() }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                        }
                    }.padding(6)
                }
            }

            GroupBox("Available to install") {
                VStack(spacing: 0) {
                    ForEach(EngineCatalogEntry.all) { entry in
                        let installed = engines.engines.contains { $0.id == entry.id }
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).fontWeight(.medium)
                                Text(entry.summary).font(.caption2).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if installed {
                                Label("Installed", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green).font(.caption)
                            } else if let p = engines.installing[entry.id] {
                                if p < 0 { ProgressView().controlSize(.small) }
                                else { ProgressView(value: p).frame(width: 90) }
                            } else {
                                Button("Install (\(entry.sizeMB) MB)") { engines.install(entry) }
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }.padding(6)
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 540, height: 460)
    }
}
