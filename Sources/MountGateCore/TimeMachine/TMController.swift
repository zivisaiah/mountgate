import Foundation

public enum TMSyncState: Equatable, Sendable {
    case idle
    case syncing
    case failed(String)
}

/// Orchestrates MountGate's Staged-mode Time Machine pipeline:
/// destination setup, backup-completion watching, and bundle → cloud syncs.
@MainActor
public final class TMController: ObservableObject {
    @Published public private(set) var destinations: [TMDestination] = []
    @Published public private(set) var syncStates: [String: TMSyncState] = [:]
    /// True while `tmutil status` reports a running backup.
    @Published public private(set) var backupRunning = false

    private let engine: RcloneEngine
    private let store: TMDestinationStore
    private var watcher: Task<Void, Never>?
    private var syncTasks: [String: Task<Void, Never>] = [:]

    /// Default staging area for the local sparsebundles.
    public static func defaultBundleDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MountGate/TimeMachine")
    }

    public init(engine: RcloneEngine, store: TMDestinationStore = TMDestinationStore()) {
        self.engine = engine
        self.store = store
        self.destinations = store.load()
    }

    public func syncState(of destination: TMDestination) -> TMSyncState {
        syncStates[destination.name] ?? .idle
    }

    /// Test hook: inject destinations without going through createDestination.
    func setDestinationsForTesting(_ list: [TMDestination]) {
        destinations = list
    }

    // MARK: - Destination lifecycle

    /// Create the local sparsebundle and register the destination.
    /// Returns the attached volume path; `tmutil setdestination` (privileged)
    /// is a separate step handled by the UI.
    @discardableResult
    public func createDestination(name: String, accountName: String,
                                  sizeGB: Int, passphrase: String?) throws -> TMDestination {
        let dir = Self.defaultBundleDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundleURL = dir.appendingPathComponent("\(name).sparsebundle")
        guard !FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw MountGateError.mountPointUnavailable(bundleURL.path)
        }
        try SparseBundle.create(at: bundleURL, volumeName: name,
                                sizeGB: sizeGB, passphrase: passphrase)
        if let passphrase {
            // Keychain storage lets the volume re-attach after reboots.
            try TMKeychain.savePassphrase(passphrase, destinationName: name)
        }
        try SparseBundle.attach(bundleURL, passphrase: passphrase)

        let destination = TMDestination(
            name: name,
            accountName: accountName,
            remotePath: "mountgate-tm/\(name).sparsebundle",
            bundleURL: bundleURL,
            sizeGB: sizeGB,
            encrypted: passphrase != nil)
        destinations.append(destination)
        try store.save(destinations)
        return destination
    }

    /// Remove a destination from MountGate (bundle is kept on disk unless
    /// `deleteBundle`; the cloud copy is never touched).
    public func removeDestination(_ destination: TMDestination, deleteBundle: Bool) throws {
        syncTasks[destination.name]?.cancel()
        if SparseBundle.isAttached(volumePath: destination.volumePath) {
            try? SparseBundle.detach(volumePath: destination.volumePath)
        }
        if deleteBundle {
            try? FileManager.default.removeItem(at: destination.bundleURL)
            TMKeychain.deletePassphrase(destinationName: destination.name)
        }
        destinations.removeAll { $0.name == destination.name }
        try store.save(destinations)
    }

    /// Re-attach destination volumes (call at app launch so backupd finds
    /// them). Encrypted bundles read their passphrase from the Keychain.
    public func attachAll() {
        for destination in destinations {
            guard !SparseBundle.isAttached(volumePath: destination.volumePath) else { continue }
            let passphrase = destination.encrypted
                ? TMKeychain.loadPassphrase(destinationName: destination.name)
                : nil
            try? SparseBundle.attach(destination.bundleURL, passphrase: passphrase)
        }
    }

    // MARK: - Backup watching

    /// Poll `tmutil status`; when a running backup finishes, sync every
    /// destination whose volume took part (conservatively: all of ours).
    public func startWatching(interval: TimeInterval = 30) {
        watcher?.cancel()
        watcher = Task { [weak self] in
            var wasRunning = false
            while !Task.isCancelled {
                let running = Self.isBackupRunning()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.backupRunning = running
                    if wasRunning && !running {
                        // A backup just completed → stage changed bands to cloud.
                        for destination in self.destinations {
                            self.requestSync(destination)
                        }
                    }
                }
                wasRunning = running
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    public func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    nonisolated static func isBackupRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["status"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.contains("Running = 1")
    }

    // MARK: - Cloud sync

    /// Queue a bundle → cloud sync; consecutive requests coalesce.
    public func requestSync(_ destination: TMDestination) {
        guard syncStates[destination.name] != .syncing else { return }
        syncStates[destination.name] = .syncing
        syncTasks[destination.name]?.cancel()
        let engine = engine
        syncTasks[destination.name] = Task { [weak self] in
            let result: Result<Void, Error> = await Task.detached {
                do {
                    try engine.run([
                        "sync", destination.bundleURL.path, destination.remoteSpec,
                        "--transfers", "8",
                        "--exclude", "*.lock",
                    ])
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success:
                self.syncStates[destination.name] = .idle
                if let index = self.destinations.firstIndex(where: { $0.name == destination.name }) {
                    self.destinations[index].lastSync = Date()
                    try? self.store.save(self.destinations)
                }
            case .failure(let error):
                self.syncStates[destination.name] = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Restore

    /// Download the cloud copy of a bundle next to `to` and attach it.
    public func restore(_ destination: TMDestination, to directory: URL) async throws -> String {
        let target = directory.appendingPathComponent("\(destination.name)-restored.sparsebundle")
        let engine = engine
        try await Task.detached {
            try engine.run(["copy", destination.remoteSpec, target.path, "--transfers", "8"])
        }.value
        let passphrase = destination.encrypted
            ? TMKeychain.loadPassphrase(destinationName: destination.name)
            : nil
        return try SparseBundle.attach(target, passphrase: passphrase)
    }
}
