import SwiftUI
import MountGateCore

@main
struct MountGateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("MountGate", systemImage: "externaldrive.badge.icloud") {
            MenuContent()
                .environmentObject(state)
                .onAppear { appDelegate.state = state }
        }

        Window("MountGate Accounts", id: "accounts") {
            AccountsView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)

        Window("Time Machine Backups", id: "timemachine") {
            TimeMachineView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}

/// Ensures every mount is torn down when the app quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            state?.controller?.unmountAllForShutdown()
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let error = state.engineError {
            Text("Engine error: \(error)")
        } else if state.remotes.isEmpty {
            Text("No accounts yet")
        } else {
            ForEach(state.remotes) { remote in
                RemoteRow(remote: remote)
            }
        }

        if let tm = state.tmController, !tm.destinations.isEmpty {
            Divider()
            ForEach(tm.destinations) { destination in
                TMMenuRow(destination: destination)
            }
        }

        Divider()
        Button("Accounts…") {
            openWindow(id: "accounts")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Time Machine…") {
            openWindow(id: "timemachine")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink {
            Text("Settings…")
        }
        if let controller = state.controller {
            Button("Open Logs Folder") {
                NSWorkspace.shared.open(controller.logDirectory)
            }
        }
        Text(state.engineVersion)
            .font(.caption)
        Divider()
        Button("Quit MountGate") {
            state.controller?.unmountAllForShutdown()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

struct TMMenuRow: View {
    @EnvironmentObject var state: AppState
    let destination: TMDestination

    var body: some View {
        let syncState = state.tmController?.syncState(of: destination) ?? .idle
        Button {
            state.tmController?.requestSync(destination)
        } label: {
            HStack {
                Image(systemName: icon(for: syncState))
                Text(label(for: syncState))
            }
        }
        .disabled(syncState == .syncing)
    }

    private func icon(for s: TMSyncState) -> String {
        switch s {
        case .idle: return "clock.arrow.circlepath"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func label(for s: TMSyncState) -> String {
        switch s {
        case .syncing: return "\(destination.name): syncing to cloud…"
        case .failed: return "\(destination.name): sync failed — retry"
        case .idle:
            if let lastSync = destination.lastSync {
                return "\(destination.name): synced \(lastSync.formatted(.relative(presentation: .named)))"
            }
            return "\(destination.name): sync to cloud"
        }
    }
}

struct RemoteRow: View {
    @EnvironmentObject var state: AppState
    let remote: Remote

    var body: some View {
        let mountState = state.controller?.state(of: remote) ?? .unmounted
        Button {
            state.toggle(remote)
        } label: {
            HStack {
                Image(systemName: icon(for: mountState))
                Text(label(for: mountState))
            }
        }
        .disabled(mountState.isBusy)

        if mountState == .mounted, let controller = state.controller {
            Button("    Open \"\(remote.name)\" in Finder") {
                NSWorkspace.shared.open(controller.mountPoint(for: remote))
            }
        }
        if case .failed(let message) = mountState {
            Text("    \(message)")
                .font(.caption)
        }
    }

    private func icon(for s: MountState) -> String {
        switch s {
        case .mounted: return "checkmark.circle.fill"
        case .mounting, .unmounting: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle.fill"
        case .unmounted: return "circle"
        }
    }

    private func label(for s: MountState) -> String {
        switch s {
        case .mounted: return "Unmount \(remote.name)"
        case .mounting: return "Mounting \(remote.name)…"
        case .unmounting: return "Unmounting \(remote.name)…"
        case .failed: return "Mount \(remote.name) (failed)"
        case .unmounted: return "Mount \(remote.name)"
        }
    }
}
