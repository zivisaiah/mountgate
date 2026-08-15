import Foundation
import Combine
@preconcurrency import UserNotifications
import MountGateCore

@MainActor
final class AppState: ObservableObject {
    @Published var remotes: [Remote] = []
    /// account name → rclone backend type, for display in the accounts list.
    @Published var accountTypes: [String: String] = [:]
    @Published var engineError: String?
    @Published var engineVersion: String = ""

    let controller: MountController?
    let configStore: ConfigStore?
    let authFlow: AuthFlow?
    let tmController: TMController?
    private var cancellables = Set<AnyCancellable>()

    init() {
        do {
            let engine = try RcloneEngine.locate()
                .withConfig(RcloneEngine.defaultConfigURL())
            let controller = MountController(engine: engine)
            let tmController = TMController(engine: engine)
            self.controller = controller
            self.configStore = ConfigStore(engine: engine)
            self.authFlow = AuthFlow(engine: engine)
            self.tmController = tmController
            controller.recoverStaleMounts()
            tmController.attachAll()
            if !tmController.destinations.isEmpty {
                tmController.startWatching()
            }
            engineVersion = (try? engine.version()) ?? "rclone (version unknown)"
            // Re-render menu rows whenever any mount or TM state changes.
            controller.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
            tmController.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
            // Notify when a mount that was up goes down unexpectedly.
            controller.$states
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newStates in
                    self?.notifyOnFailures(newStates)
                }
                .store(in: &cancellables)
            applyMountSettings()
            refreshRemotes()
        } catch {
            controller = nil
            configStore = nil
            authFlow = nil
            tmController = nil
            engineError = error.localizedDescription
        }
    }

    func refreshRemotes() {
        guard let configStore else { return }
        remotes = (try? configStore.remotes()) ?? []
        let dump = (try? configStore.dump()) ?? [:]
        accountTypes = dump.compactMapValues { $0["type"] }
    }

    func toggle(_ remote: Remote) {
        guard let controller else { return }
        Task {
            if controller.state(of: remote) == .mounted {
                await controller.unmount(remote)
            } else {
                await controller.mount(remote)
            }
        }
    }

    /// Create an account; runs the browser OAuth flow first when needed.
    func addAccount(provider: Provider, name: String,
                    fieldValues: [String: String]) async throws {
        guard let configStore, let authFlow else { return }
        var options = provider.constantOptions
        for (key, value) in fieldValues where !value.isEmpty {
            options[key] = value
        }
        if provider.usesOAuth {
            // GCS with a service-account file needs no browser sign-in.
            let needsBrowser = options["service_account_file"]?.isEmpty ?? true
            if needsBrowser {
                options["token"] = try await authFlow.authorize(
                    rcloneType: provider.rcloneType,
                    clientID: options["client_id"],
                    clientSecret: options["client_secret"])
            }
        }
        try configStore.createRemote(name: name, type: provider.rcloneType,
                                     options: options)
        refreshRemotes()
    }

    /// Push cache settings from UserDefaults into the mount controller.
    func applyMountSettings() {
        guard let controller else { return }
        let sizeGB = UserDefaults.standard.object(forKey: "cacheMaxSizeGB") as? Int ?? 10
        let ageHours = UserDefaults.standard.object(forKey: "cacheMaxAgeHours") as? Int ?? 24
        controller.extraMountArguments = [
            "--vfs-cache-max-size", "\(sizeGB)G",
            "--vfs-cache-max-age", "\(ageHours)h",
        ]
    }

    private var lastStates: [String: MountState] = [:]

    private func notifyOnFailures(_ newStates: [String: MountState]) {
        defer { lastStates = newStates }
        for (name, state) in newStates {
            guard case .failed(let message) = state,
                  lastStates[name] == .mounted else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(name) disconnected"
            content.body = message
            let request = UNNotificationRequest(
                identifier: "mount-failed-\(name)-\(Date().timeIntervalSince1970)",
                content: content, trigger: nil)
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert]) { granted, _ in
                guard granted else { return }
                center.add(request)
            }
        }
    }

    func deleteAccount(name: String) async {
        guard let configStore, let controller else { return }
        let remote = Remote(name: name)
        if controller.state(of: remote) == .mounted {
            await controller.unmount(remote)
        }
        try? configStore.deleteRemote(name: name)
        refreshRemotes()
    }
}
