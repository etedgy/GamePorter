import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engines: EngineManager
    @EnvironmentObject var bottleManager: BottleManager
    @State private var selection: UUID?
    @State private var showNewBottle = false
    @State private var showEngines = false
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Bottles") {
                    ForEach(bottleManager.bottles) { bottle in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bottle.name)
                                if let op = bottleManager.busy[bottle.id] {
                                    Text(op).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "cylinder.split.1x2")
                                .foregroundStyle(.teal)
                        }
                        .tag(bottle.id)
                        .contextMenu {
                            Button("Open C: Drive") { bottleManager.openDriveC(bottle) }
                            Button("Kill All Processes") { bottleManager.killAll(in: bottle) }
                            Divider()
                            Button("Delete Bottle", role: .destructive) {
                                bottleManager.deleteBottle(bottle)
                                if selection == bottle.id { selection = nil }
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .toolbar {
                ToolbarItem {
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem {
                    Button { showEngines = true } label: {
                        Label("Engines", systemImage: "cpu")
                    }
                }
                ToolbarItem {
                    Button {
                        showNewBottle = true
                    } label: {
                        Label("New Bottle", systemImage: "plus")
                    }
                    .disabled(engines.isEmpty)
                }
            }
        } detail: {
            if !engines.isEmpty {
                if let id = selection,
                   let bottle = bottleManager.bottles.first(where: { $0.id == id }) {
                    BottleDetailView(bottle: bottle)
                        .id(bottle.id)
                } else {
                    EmptyStateView(showNewBottle: $showNewBottle)
                }
            } else {
                SetupView()
            }
        }
        .sheet(isPresented: $showNewBottle) {
            NewBottleSheet(engines: engines.engines) { name, winVer, engineID, renderer in
                bottleManager.createBottle(named: name, windowsVersion: winVer,
                                           engineID: engineID, renderer: renderer)
            }
        }
        .sheet(isPresented: $showEngines) {
            EnginesView().environmentObject(engines)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Error", isPresented: Binding(
            get: { bottleManager.lastError != nil },
            set: { if !$0 { bottleManager.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bottleManager.lastError ?? "")
        }
    }
}

struct EmptyStateView: View {
    @Binding var showNewBottle: Bool
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No bottle selected")
                .font(.title2)
            Text("A bottle is an isolated Windows environment.\nCreate one per game or launcher.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Create a Bottle") { showNewBottle = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NewBottleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var windowsVersion = "win10"
    @State private var engineID: String
    @State private var renderer: RendererKind
    let engines: [Engine]
    let onCreate: (String, String, String, RendererKind) -> Void

    init(engines: [Engine], onCreate: @escaping (String, String, String, RendererKind) -> Void) {
        self.engines = engines
        self.onCreate = onCreate
        let first = engines.first
        _engineID = State(initialValue: first?.id ?? "")
        _renderer = State(initialValue: first?.defaultRenderer ?? .wined3d)
    }

    static let versions = [
        ("win10", "Windows 10 (recommended)"),
        ("win11", "Windows 11"),
        ("win7", "Windows 7"),
        ("winxp64", "Windows XP"),
    ]

    var selectedEngine: Engine? { engines.first { $0.id == engineID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Bottle").font(.title3.bold())
            TextField("Name (e.g. Steam, Skyrim)", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("Windows version", selection: $windowsVersion) {
                ForEach(Self.versions, id: \.0) { v in
                    Text(v.1).tag(v.0)
                }
            }
            Picker("Engine", selection: $engineID) {
                ForEach(engines) { e in
                    Text("\(e.name) — \(e.versionNote)").tag(e.id)
                }
            }
            .onChange(of: engineID) { _, _ in
                if let e = selectedEngine, !e.supportedRenderers.contains(renderer) {
                    renderer = e.defaultRenderer
                }
            }
            if let e = selectedEngine {
                Picker("Renderer", selection: $renderer) {
                    ForEach(e.supportedRenderers) { r in
                        Text(r.label).tag(r)
                    }
                }
                Text(renderer.blurb)
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(name.isEmpty ? "New Bottle" : name, windowsVersion, engineID, renderer)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || engineID.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
