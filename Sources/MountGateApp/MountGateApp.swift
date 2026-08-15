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

    var body: some View {
        if let error = state.engineError {
            Text("Engine error: \(error)")
        } else if state.remotes.isEmpty {
            Text("No rclone remotes configured")
            Text("Add remotes with: rclone config")
                .font(.caption)
        } else {
            ForEach(state.remotes) { remote in
                RemoteRow(remote: remote)
            }
        }

        Divider()
        Button("Refresh Remotes") { state.refreshRemotes() }
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
