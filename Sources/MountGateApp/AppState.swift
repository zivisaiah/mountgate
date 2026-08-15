import Foundation
import Combine
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
    private var cancellables = Set<AnyCancellable>()

    init() {
        do {
            let engine = try RcloneEngine.locate()
                .withConfig(RcloneEngine.defaultConfigURL())
            let controller = MountController(engine: engine)
            self.controller = controller
            self.configStore = ConfigStore(engine: engine)
            self.authFlow = AuthFlow(engine: engine)
            controller.recoverStaleMounts()
            engineVersion = (try? engine.version()) ?? "rclone (version unknown)"
            // Re-render menu rows whenever any mount's state changes.
            controller.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
            refreshRemotes()
        } catch {
            controller = nil
            configStore = nil
            authFlow = nil
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
