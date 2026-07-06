import SwiftUI
import UniformTypeIdentifiers

struct BottleDetailView: View {
    @EnvironmentObject var bottleManager: BottleManager
    @State var bottle: Bottle
    @State private var discovered: [DiscoveredProgram] = []
    @State private var showRunPicker = false
    @State private var showInstallerPicker = false

    var isBusy: Bool { bottleManager.busy[bottle.id] != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let op = bottleManager.busy[bottle.id] {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(op).foregroundStyle(.secondary)
                    }
                }
                actionBar
                optionsSection
                pinnedSection
                discoveredSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { refreshPrograms() }
        .fileImporter(isPresented: $showRunPicker,
                      allowedContentTypes: [.exe, .item]) { result in
            if case .success(let url) = result {
                bottleManager.launch(exe: url.path, in: bottle)
            }
        }
        .fileImporter(isPresented: $showInstallerPicker,
                      allowedContentTypes: [.exe, .item]) { result in
            if case .success(let url) = result {
                bottleManager.runInstaller(url, in: bottle)
            }
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bottle.name).font(.largeTitle.bold())
            Text("\(windowsLabel) · created \(bottle.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .foregroundStyle(.secondary)
        }
    }

    var windowsLabel: String {
        NewBottleSheet.versions.first { $0.0 == bottle.windowsVersion }?.1 ?? bottle.windowsVersion
    }

    var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                showRunPicker = true
            } label: { Label("Run…", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
            Button {
                showInstallerPicker = true
            } label: { Label("Install App…", systemImage: "shippingbox") }
            Button {
                bottleManager.installSteam(in: bottle)
            } label: { Label("Install Steam", systemImage: "cloud") }
            Menu {
                Button("Wine Configuration (winecfg)") { bottleManager.runTool("winecfg", in: bottle) }
                Button("Task Manager") { bottleManager.runTool("taskmgr", in: bottle) }
                Button("Registry Editor") { bottleManager.runTool("regedit", in: bottle) }
                Button("Command Prompt") { bottleManager.runTool("wineconsole", in: bottle) }
                Divider()
                Button("Open C: Drive in Finder") { bottleManager.openDriveC(bottle) }
                Button("Kill All Processes", role: .destructive) { bottleManager.killAll(in: bottle) }
            } label: { Label("Tools", systemImage: "wrench.and.screwdriver") }
        }
        .disabled(isBusy)
    }

    var optionsSection: some View {
        GroupBox("Launch Options") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("ESYNC (faster synchronization)", isOn: binding(\.esync))
                Toggle("Metal HUD (FPS overlay)", isOn: binding(\.metalHUD))
                Toggle("Advertise AVX to games (Rosetta)", isOn: binding(\.advertiseAVX))
                Toggle("Retina mode", isOn: Binding(
                    get: { bottle.retinaMode },
                    set: { newValue in
                        bottle.retinaMode = newValue
                        bottleManager.setRetina(newValue, in: bottle)
                        bottleManager.update(bottle)
                    }))
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func binding(_ keyPath: WritableKeyPath<Bottle, Bool>) -> Binding<Bool> {
        Binding(
            get: { bottle[keyPath: keyPath] },
            set: { newValue in
                bottle[keyPath: keyPath] = newValue
                bottleManager.update(bottle)
            })
    }

    var pinnedSection: some View {
        Group {
            if !bottle.pinned.isEmpty {
                GroupBox("Pinned") {
                    VStack(spacing: 0) {
                        ForEach(bottle.pinned) { prog in
                            HStack {
                                Image(systemName: "pin.fill").foregroundStyle(.orange).font(.caption)
                                Text(prog.name)
                                Spacer()
                                Button {
                                    bottleManager.launch(exe: prog.unixPath,
                                                         arguments: prog.arguments, in: bottle)
                                } label: { Image(systemName: "play.circle.fill").font(.title3) }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.teal)
                                Button {
                                    bottle.pinned.removeAll { $0.id == prog.id }
                                    bottleManager.update(bottle)
                                } label: { Image(systemName: "pin.slash") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    var discoveredSection: some View {
        GroupBox {
            VStack(spacing: 0) {
                if discovered.isEmpty {
                    Text("No programs found yet. Install something, then refresh.")
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    ForEach(discovered) { prog in
                        HStack {
                            Image(systemName: "app.dashed")
                            VStack(alignment: .leading) {
                                Text(prog.name)
                                Text(windowsPath(prog.unixPath))
                                    .font(.caption2).foregroundStyle(.tertiary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                bottleManager.launch(exe: prog.unixPath, in: bottle)
                            } label: { Image(systemName: "play.circle.fill").font(.title3) }
                                .buttonStyle(.plain)
                                .foregroundStyle(.teal)
                            Button {
                                bottle.pinned.append(PinnedProgram(name: prog.name, unixPath: prog.unixPath))
                                bottleManager.update(bottle)
                            } label: { Image(systemName: "pin") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .disabled(bottle.pinned.contains { $0.unixPath == prog.unixPath })
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .padding(6)
        } label: {
            HStack {
                Text("Programs in this bottle")
                Spacer()
                Button {
                    refreshPrograms()
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
            }
        }
    }

    func windowsPath(_ unixPath: String) -> String {
        let cPath = bottle.driveC.path
        if unixPath.hasPrefix(cPath) {
            return "C:" + unixPath.dropFirst(cPath.count).replacingOccurrences(of: "/", with: "\\")
        }
        return unixPath
    }

    func refreshPrograms() {
        discovered = bottleManager.discoverPrograms(in: bottle)
    }
}

extension UTType {
    static let exe = UTType(filenameExtension: "exe") ?? .item
}
