import SwiftUI
import ServiceManagement
import MountGateCore

/// App settings, persisted in UserDefaults.
struct SettingsView: View {
    @AppStorage("cacheMaxSizeGB") private var cacheMaxSizeGB = 10
    @AppStorage("cacheMaxAgeHours") private var cacheMaxAgeHours = 24
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("General") {
                Toggle("Start MountGate at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginItemError = nil
                        } catch {
                            loginItemError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Mount cache") {
                HStack {
                    TextField("Max cache size", value: $cacheMaxSizeGB, format: .number)
                        .frame(width: 70)
                    Text("GB of local disk for the write/read cache")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Max cache age", value: $cacheMaxAgeHours, format: .number)
                        .frame(width: 70)
                    Text("hours before unused cached data is dropped")
                        .foregroundStyle(.secondary)
                }
                Text("Applies to newly started mounts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onChange(of: cacheMaxSizeGB) { state.applyMountSettings() }
        .onChange(of: cacheMaxAgeHours) { state.applyMountSettings() }
    }
}
