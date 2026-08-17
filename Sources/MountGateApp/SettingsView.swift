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
                LabeledContent("Max cache size") {
                    HStack(spacing: 4) {
                        TextField("", value: $cacheMaxSizeGB, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("GB")
                    }
                }
                LabeledContent("Max cache age") {
                    HStack(spacing: 4) {
                        TextField("", value: $cacheMaxAgeHours, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("hours")
                    }
                }
                Text("Local disk budget for each mount’s read/write cache and how long unused data is kept. Applies to newly started mounts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Forms are scrollable and have no intrinsic height; without an
        // explicit height the hosting window collapses to an empty view.
        .frame(width: 440, height: 320)
        .onChange(of: cacheMaxSizeGB) { state.applyMountSettings() }
        .onChange(of: cacheMaxAgeHours) { state.applyMountSettings() }
    }
}
