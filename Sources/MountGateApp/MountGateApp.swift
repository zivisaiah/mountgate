import AppKit
import SwiftUI
import MountGateCore

// AppKit lifecycle, not SwiftUI's App/MenuBarExtra: on macOS 26 SwiftUI's
// MenuBarExtra can silently fail to create its status item (no window, no
// entry in Menu Bar settings), while NSStatusItem works reliably.
@main
enum AppMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) var state: AppState!
    private var statusItem: NSStatusItem!
    private var windows: [String: NSWindow] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("didFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        state = AppState()
        debugLog("state ready, engineError=\(state.engineError ?? "nil")")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "externaldrive.badge.icloud",
                                   accessibilityDescription: "MountGate")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false // we manage isEnabled per item
        statusItem.menu = menu
        debugLog("statusItem created, visible=\(statusItem.isVisible), window=\(String(describing: statusItem.button?.window?.frame))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            self.debugLog("after 3s: visible=\(self.statusItem.isVisible), window=\(String(describing: button.window?.frame)), onScreen=\(button.window?.isVisible ?? false), image=\(String(describing: button.image?.size))")
        }
    }

    private func debugLog(_ message: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MountGate/app.log")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = "\(Date()) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.controller?.unmountAllForShutdown()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        state.refreshRemotes()

        if let error = state.engineError {
            menu.addItem(disabled("Engine error: \(error)"))
        } else if state.remotes.isEmpty {
            menu.addItem(disabled("No accounts yet"))
        } else {
            for remote in state.remotes {
                addRemoteItems(to: menu, remote: remote)
            }
        }

        if let tm = state.tmController, !tm.destinations.isEmpty {
            menu.addItem(.separator())
            for destination in tm.destinations {
                addTMItem(to: menu, destination: destination)
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Accounts…", #selector(openAccounts)))
        menu.addItem(item("Time Machine…", #selector(openTimeMachine)))
        menu.addItem(item("Settings…", #selector(openSettings)))
        menu.addItem(item("Open Logs Folder", #selector(openLogs)))
        menu.addItem(.separator())
        let quit = item("Quit MountGate", #selector(quitApp))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func addRemoteItems(to menu: NSMenu, remote: Remote) {
        let mountState = state.controller?.state(of: remote) ?? .unmounted
        let title: String
        let symbol: String
        switch mountState {
        case .mounted: title = "Unmount \(remote.name)"; symbol = "checkmark.circle.fill"
        case .mounting: title = "Mounting \(remote.name)…"; symbol = "arrow.triangle.2.circlepath"
        case .unmounting: title = "Unmounting \(remote.name)…"; symbol = "arrow.triangle.2.circlepath"
        case .failed: title = "Mount \(remote.name) (failed)"; symbol = "exclamationmark.triangle.fill"
        case .unmounted: title = "Mount \(remote.name)"; symbol = "circle"
        }
        let menuItem = item(title, #selector(toggleRemote(_:)))
        menuItem.representedObject = remote.name
        menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        menuItem.isEnabled = !mountState.isBusy
        menu.addItem(menuItem)

        if mountState == .mounted {
            let open = item("    Open “\(remote.name)” in Finder", #selector(openRemoteInFinder(_:)))
            open.representedObject = remote.name
            menu.addItem(open)
        }
        if case .failed(let message) = mountState {
            menu.addItem(disabled("    \(message)"))
        }
    }

    private func addTMItem(to menu: NSMenu, destination: TMDestination) {
        let syncState = state.tmController?.syncState(of: destination) ?? .idle
        let title: String
        switch syncState {
        case .syncing: title = "\(destination.name): syncing to cloud…"
        case .failed: title = "\(destination.name): sync failed — retry"
        case .idle:
            if let lastSync = destination.lastSync {
                title = "\(destination.name): synced \(lastSync.formatted(.relative(presentation: .named)))"
            } else {
                title = "\(destination.name): sync to cloud"
            }
        }
        let menuItem = item(title, #selector(syncDestination(_:)))
        menuItem.representedObject = destination.name
        menuItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath",
                                 accessibilityDescription: nil)
        menuItem.isEnabled = syncState != .syncing
        menu.addItem(menuItem)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        return menuItem
    }

    // MARK: - Actions

    @objc private func toggleRemote(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        state.toggle(Remote(name: name))
    }

    @objc private func openRemoteInFinder(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let controller = state.controller else { return }
        NSWorkspace.shared.open(controller.mountPoint(for: Remote(name: name)))
    }

    @objc private func syncDestination(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let tm = state.tmController,
              let destination = tm.destinations.first(where: { $0.name == name }) else { return }
        tm.requestSync(destination)
    }

    @objc private func openAccounts() {
        showWindow(id: "accounts", title: "MountGate Accounts",
                   size: NSSize(width: 460, height: 360)) {
            AnyView(AccountsView().environmentObject(self.state))
        }
    }

    @objc private func openTimeMachine() {
        showWindow(id: "timemachine", title: "Time Machine Backups",
                   size: NSSize(width: 560, height: 380)) {
            AnyView(TimeMachineView().environmentObject(self.state))
        }
    }

    @objc private func openSettings() {
        showWindow(id: "settings", title: "MountGate Settings",
                   size: NSSize(width: 440, height: 320)) {
            AnyView(SettingsView().environmentObject(self.state))
        }
    }

    @objc private func openLogs() {
        guard let controller = state.controller else { return }
        NSWorkspace.shared.open(controller.logDirectory)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Window management

    private func showWindow(id: String, title: String, size: NSSize,
                            content: @escaping () -> AnyView) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content())
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
