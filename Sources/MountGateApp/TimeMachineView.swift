import SwiftUI
import MountGateCore

/// Time Machine window: managed destinations, sync status, setup wizard.
struct TimeMachineView: View {
    @EnvironmentObject var state: AppState
    @State private var showingSetup = false
    @State private var restoreMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let tm = state.tmController {
                if tm.destinations.isEmpty {
                    ContentUnavailableView(
                        "No Backup Destinations",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Set up Time Machine backups to your cloud storage."))
                } else {
                    List(tm.destinations) { destination in
                        DestinationRow(destination: destination,
                                       restoreMessage: $restoreMessage)
                    }
                }
                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.caption)
                        .padding(.horizontal)
                }
                Divider()
                HStack {
                    Button {
                        showingSetup = true
                    } label: {
                        Label("Set Up Backup Destination", systemImage: "plus")
                    }
                    .disabled(state.remotes.isEmpty)
                    if state.remotes.isEmpty {
                        Text("Add a cloud account first")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if tm.backupRunning {
                        Label("Backup running…", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                    }
                }
                .padding(10)
            } else {
                ContentUnavailableView("Engine unavailable",
                                       systemImage: "exclamationmark.triangle")
            }
        }
        .frame(minWidth: 520, minHeight: 340)
        .sheet(isPresented: $showingSetup) {
            TMSetupSheet()
                .environmentObject(state)
        }
    }
}

private struct DestinationRow: View {
    @EnvironmentObject var state: AppState
    let destination: TMDestination
    @Binding var restoreMessage: String?

    var body: some View {
        let tm = state.tmController
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: destination.encrypted ? "lock.shield" : "shield")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name).font(.headline)
                Text("\(destination.sizeGB) GB → \(destination.remoteSpec)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch tm?.syncState(of: destination) ?? .idle {
            case .syncing:
                ProgressView().controlSize(.small)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(message)
            case .idle:
                EmptyView()
            }
            Button("Sync Now") { tm?.requestSync(destination) }
                .disabled(tm?.syncState(of: destination) == .syncing)
            Menu {
                Button("Restore from Cloud…") { restore() }
                Button("Remove (keep local bundle)", role: .destructive) {
                    try? tm?.removeDestination(destination, deleteBundle: false)
                }
                Button("Remove and delete local bundle", role: .destructive) {
                    try? tm?.removeDestination(destination, deleteBundle: true)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        var parts: [String] = []
        parts.append(SparseBundle.isAttached(volumePath: destination.volumePath)
                     ? "volume attached" : "volume not attached")
        if let lastSync = destination.lastSync {
            parts.append("synced \(lastSync.formatted(.relative(presentation: .named)))")
        } else {
            parts.append("never synced to cloud")
        }
        return parts.joined(separator: " · ")
    }

    private func restore() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Restore Here"
        panel.message = "Choose where to download the backup bundle"
        guard panel.runModal() == .OK, let url = panel.url,
              let tm = state.tmController else { return }
        restoreMessage = "Downloading backup — this can take a while…"
        Task {
            do {
                let volume = try await tm.restore(destination, to: url)
                restoreMessage = "Restored and attached at \(volume). Browse it in Finder or enter Time Machine."
                NSWorkspace.shared.open(URL(fileURLWithPath: volume))
            } catch {
                restoreMessage = "Restore failed: \(error.localizedDescription)"
            }
        }
    }
}

/// Setup wizard: create bundle → grant FDA → register with Time Machine.
private struct TMSetupSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = "MountGate Backup"
    @State private var accountName = ""
    @State private var sizeGB = 500
    @State private var encrypt = true
    @State private var passphrase = ""
    @State private var created: TMDestination?
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(created == nil ? "Set Up Backup Destination" : "Add to Time Machine")
                .font(.title2).bold()

            if created == nil {
                configForm
            } else {
                registerStep
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { accountName = state.remotes.first?.name ?? "" }
    }

    @ViewBuilder private var configForm: some View {
        TextField("Destination name", text: $name)
            .textFieldStyle(.roundedBorder)
        Picker("Cloud account", selection: $accountName) {
            ForEach(state.remotes) { remote in
                Text(remote.name).tag(remote.name)
            }
        }
        HStack {
            Text("Size limit")
            TextField("GB", value: $sizeGB, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text("GB — Time Machine fills at most this much cloud storage")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Toggle("Encrypt backup (AES-256)", isOn: $encrypt)
        if encrypt {
            SecureField("Encryption passphrase", text: $passphrase)
                .textFieldStyle(.roundedBorder)
            Text("Keep this passphrase safe — without it the backup cannot be opened.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let errorMessage {
            Text(errorMessage).font(.caption).foregroundStyle(.red)
        }
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(working ? "Creating…" : "Create") { create() }
                .keyboardShortcut(.defaultAction)
                .disabled(working || name.isEmpty || accountName.isEmpty
                          || (encrypt && passphrase.isEmpty))
        }
    }

    @ViewBuilder private var registerStep: some View {
        Label("Backup volume created and attached.", systemImage: "checkmark.circle.fill")
        if !PrivilegedOps.hasFullDiskAccess() {
            Label("MountGate needs Full Disk Access to register the destination.",
                  systemImage: "exclamationmark.shield")
            Button("Open Privacy Settings") {
                PrivilegedOps.openFullDiskAccessSettings()
            }
            Text("Grant access, then quit and reopen MountGate and press the button below.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let errorMessage {
            Text(errorMessage).font(.caption).foregroundStyle(.red)
                .textSelection(.enabled)
        }
        HStack {
            Spacer()
            Button("Later") { dismiss() }
            Button("Add to Time Machine") { register() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func create() {
        working = true
        errorMessage = nil
        Task {
            do {
                created = try state.tmController?.createDestination(
                    name: name, accountName: accountName, sizeGB: sizeGB,
                    passphrase: encrypt ? passphrase : nil)
            } catch {
                errorMessage = error.localizedDescription
            }
            working = false
        }
    }

    private func register() {
        guard let created else { return }
        errorMessage = nil
        do {
            try PrivilegedOps.addTMDestination(volumePath: created.volumePath)
            state.tmController?.startWatching()
            dismiss()
        } catch {
            errorMessage = "Time Machine refused: \(error.localizedDescription)"
        }
    }
}
