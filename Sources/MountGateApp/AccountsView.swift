import SwiftUI
import MountGateCore

/// Accounts management window: list, add, delete.
struct AccountsView: View {
    @EnvironmentObject var state: AppState
    @State private var showingAdd = false

    var body: some View {
        VStack(spacing: 0) {
            if state.remotes.isEmpty {
                ContentUnavailableView(
                    "No Accounts",
                    systemImage: "externaldrive.badge.icloud",
                    description: Text("Add a cloud storage account to mount it in Finder."))
            } else {
                List(state.remotes) { remote in
                    HStack {
                        Image(systemName: "externaldrive.connected.to.line.below")
                        VStack(alignment: .leading) {
                            Text(remote.name).font(.headline)
                            Text(typeLabel(for: remote))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await state.deleteAccount(name: remote.name) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this account")
                    }
                    .padding(.vertical, 2)
                }
            }
            Divider()
            HStack {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
                Spacer()
            }
            .padding(10)
        }
        .frame(minWidth: 440, minHeight: 320)
        .sheet(isPresented: $showingAdd) {
            AddAccountSheet()
                .environmentObject(state)
        }
    }

    private func typeLabel(for remote: Remote) -> String {
        let type = state.accountTypes[remote.name] ?? "unknown"
        return ProviderCatalog.all.first { $0.rcloneType == type }?.label ?? type
    }
}

/// The add-account wizard: provider picker + dynamic field form.
struct AddAccountSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var provider: Provider = ProviderCatalog.s3
    @State private var name = ""
    @State private var values: [String: String] = [:]
    @State private var s3Preset: S3Preset = ProviderCatalog.s3Presets[0]
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Account").font(.title2).bold()

            Picker("Service", selection: Binding(
                get: { provider.id },
                set: { provider = ProviderCatalog.provider(id: $0) ?? ProviderCatalog.s3 }
            )) {
                ForEach(ProviderCatalog.all) { p in
                    Text(p.label).tag(p.id)
                }
            }

            TextField("Account name", text: $name, prompt: Text("my-storage"))
                .textFieldStyle(.roundedBorder)

            if provider.id == "s3" {
                Picker("Preset", selection: $s3Preset) {
                    ForEach(ProviderCatalog.s3Presets) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
            }

            ForEach(provider.fields) { field in
                let binding = Binding(
                    get: { values[field.key] ?? "" },
                    set: { values[field.key] = $0 })
                if field.secure {
                    SecureField(field.label, text: binding,
                                prompt: Text(field.placeholder))
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField(field.label, text: binding,
                              prompt: Text(placeholder(for: field)))
                        .textFieldStyle(.roundedBorder)
                }
            }

            if provider.usesOAuth {
                Label("Your browser will open to sign in with Google.",
                      systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(saving ? "Connecting…" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || name.isEmpty || !requiredFilled)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var requiredFilled: Bool {
        provider.fields.filter(\.required)
            .allSatisfy { !(values[$0.key] ?? "").isEmpty }
    }

    private func placeholder(for field: ProviderField) -> String {
        if provider.id == "s3" && field.key == "endpoint" {
            return s3Preset.endpointPlaceholder
        }
        return field.placeholder
    }

    private func save() {
        saving = true
        errorMessage = nil
        var fieldValues = values
        if provider.id == "s3" {
            fieldValues["provider"] = s3Preset.provider
        }
        let provider = provider
        let name = name
        Task {
            do {
                try await state.addAccount(provider: provider, name: name,
                                           fieldValues: fieldValues)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            saving = false
        }
    }
}
