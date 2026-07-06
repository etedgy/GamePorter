import SwiftUI

struct ContentView: View {
    @EnvironmentObject var toolkit: ToolkitManager
    @EnvironmentObject var bottleManager: BottleManager
    @State private var selection: UUID?
    @State private var showNewBottle = false

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
                    Button {
                        showNewBottle = true
                    } label: {
                        Label("New Bottle", systemImage: "plus")
                    }
                    .disabled(toolkit.wineBin == nil)
                }
            }
        } detail: {
            if case .installed = toolkit.status {
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
            NewBottleSheet { name, winVer in
                bottleManager.createBottle(named: name, windowsVersion: winVer)
            }
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
    let onCreate: (String, String) -> Void

    static let versions = [
        ("win10", "Windows 10 (recommended)"),
        ("win11", "Windows 11"),
        ("win7", "Windows 7"),
        ("winxp64", "Windows XP"),
    ]

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
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(name.isEmpty ? "New Bottle" : name, windowsVersion)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
