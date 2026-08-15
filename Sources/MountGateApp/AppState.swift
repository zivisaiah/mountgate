import Foundation
import Combine
import MountGateCore

@MainActor
final class AppState: ObservableObject {
    @Published var remotes: [Remote] = []
    @Published var engineError: String?
    @Published var engineVersion: String = ""

    let controller: MountController?
    private var cancellables = Set<AnyCancellable>()

    init() {
        do {
            let engine = try RcloneEngine.locate()
            let controller = MountController(engine: engine)
            self.controller = controller
            controller.recoverStaleMounts()
            engineVersion = (try? engine.version()) ?? "rclone (version unknown)"
            remotes = (try? engine.listRemotes()) ?? []
            // Re-render menu rows whenever any mount's state changes.
            controller.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        } catch {
            controller = nil
            engineError = error.localizedDescription
        }
    }

    func refreshRemotes() {
        guard let controller else { return }
        // listRemotes is cheap; run it off the main thread anyway.
        Task {
            let engine = try? RcloneEngine.locate()
            let found = (try? engine?.listRemotes()) ?? []
            await MainActor.run { self.remotes = found }
            _ = controller // keep reference semantics obvious
        }
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
}
