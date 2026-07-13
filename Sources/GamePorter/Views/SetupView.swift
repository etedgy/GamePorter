import SwiftUI

/// Shown only when no engine is installed yet — installs the first one.
struct SetupView: View {
    @EnvironmentObject var engines: EngineManager

    var recommended: EngineCatalogEntry {
        // The self-built engine runs the widest range (incl. demanding DX12 titles).
        EngineCatalogEntry.all.first { $0.kind == .gpwine }
            ?? EngineCatalogEntry.all.first { $0.kind == .vanilla }
            ?? EngineCatalogEntry.all[0]
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 56))
                .foregroundStyle(.teal)
            Text("Welcome to GamePorter")
                .font(.title.bold())
            Text("Install a Wine engine to get started. You can add more later\nand pick which one each game runs on.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            ForEach(EngineCatalogEntry.all) { entry in
                let isRec = entry.id == recommended.id
                GroupBox {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.name).fontWeight(.semibold)
                                if isRec {
                                    Text("RECOMMENDED").font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.teal.opacity(0.2)).clipShape(Capsule())
                                }
                            }
                            Text(entry.summary).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if let p = engines.installing[entry.id] {
                            if p < 0 { ProgressView { Text("Extracting…").font(.caption) } }
                            else { ProgressView(value: p).frame(width: 100) }
                        } else if isRec {
                            Button("Install (\(entry.sizeMB) MB)") { engines.install(entry) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Install (\(entry.sizeMB) MB)") { engines.install(entry) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(6)
                }
                .frame(width: 460)
            }

            if let err = engines.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
