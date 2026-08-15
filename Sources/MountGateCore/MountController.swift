import Foundation

/// Owns one `rclone nfsmount` process per active mount and tracks its lifecycle.
///
/// rclone's nfsmount runs a localhost NFS server and asks macOS's built-in NFS
/// client to mount it — no kernel extensions involved. We keep one supervised
/// child process per mount; SIGINT triggers rclone's own clean unmount.
@MainActor
public final class MountController: ObservableObject {
    @Published public private(set) var states: [String: MountState] = [:]

    private let engine: RcloneEngine
    private var processes: [String: Process] = [:]
    /// Remotes we are deliberately unmounting, so the termination handler
    /// can tell an expected exit from a crash.
    private var expectedExits: Set<String> = []

    /// Directory under which per-remote mount points are created (~/MountGate).
    public let mountRoot: URL
    /// Directory for per-mount rclone log files.
    public let logDirectory: URL

    public init(engine: RcloneEngine,
                mountRoot: URL? = nil,
                logDirectory: URL? = nil) {
        self.engine = engine
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.mountRoot = mountRoot ?? home.appendingPathComponent("MountGate")
        self.logDirectory = logDirectory
            ?? home.appendingPathComponent("Library/Logs/MountGate")
    }

    public func state(of remote: Remote) -> MountState {
        states[remote.name] ?? .unmounted
    }

    public func mountPoint(for remote: Remote) -> URL {
        mountRoot.appendingPathComponent(remote.name)
    }

    public func logFile(for remote: Remote) -> URL {
        logDirectory.appendingPathComponent("\(remote.name).log")
    }

    // MARK: - Mounting

    public func mount(_ remote: Remote) async {
        guard !(states[remote.name]?.isBusy ?? false),
              states[remote.name] != .mounted else { return }
        states[remote.name] = .mounting

        let point = mountPoint(for: remote)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: mountRoot, withIntermediateDirectories: true)
            try fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(at: point, withIntermediateDirectories: true)
        } catch {
            states[remote.name] = .failed("Cannot create mount point: \(error.localizedDescription)")
            return
        }

        // A stale NFS mount from a previous crash makes the directory unusable.
        if Self.isMounted(path: point.path) {
            forceUnmount(path: point.path)
        }

        let process = Process()
        process.executableURL = engine.binaryURL
        process.arguments = [
            "nfsmount", remote.spec, point.path,
            "--volname", remote.name,
            "--vfs-cache-mode", "full",
            "--dir-cache-time", "30s",
            "--log-file", logFile(for: remote).path,
            "--log-level", "INFO",
        ]
        let name = remote.name
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.processDidExit(remote: name, status: proc.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            states[remote.name] = .failed("Cannot launch rclone: \(error.localizedDescription)")
            return
        }
        processes[remote.name] = process

        // Wait for the NFS volume to actually appear (or rclone to die).
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if !process.isRunning {
                let hint = Self.lastLogLine(of: logFile(for: remote))
                states[remote.name] = .failed(hint ?? "rclone exited during mount")
                processes[remote.name] = nil
                return
            }
            if Self.isMounted(path: point.path) {
                states[remote.name] = .mounted
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        // Timed out: kill the child and report.
        expectedExits.insert(remote.name)
        process.terminate()
        states[remote.name] = .failed("Timed out waiting for the volume to mount")
    }

    // MARK: - Unmounting

    /// Unmount by running `umount` on the mount point: rclone's nfsmount
    /// detects the unmount, flushes its VFS cache, and exits on its own.
    /// (SIGINT does NOT trigger a clean unmount — verified on macOS 26.)
    public func unmount(_ remote: Remote) async {
        guard !(states[remote.name]?.isBusy ?? false) else { return }
        let point = mountPoint(for: remote).path
        guard let process = processes[remote.name] else {
            // No child of ours — still try to clean up the mount point.
            if Self.isMounted(path: point) { forceUnmount(path: point) }
            states[remote.name] = .unmounted
            return
        }
        states[remote.name] = .unmounting
        expectedExits.insert(remote.name)
        runUmount(path: point, force: false)

        let deadline = Date().addingTimeInterval(15)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        if process.isRunning {
            // Graceful path failed (open files, hung server) — force it.
            forceUnmount(path: point)
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning { process.terminate() }
        }
        processes[remote.name] = nil
        states[remote.name] = .unmounted
    }

    /// Synchronous best-effort teardown for app termination.
    public func unmountAllForShutdown() {
        for name in processes.keys {
            expectedExits.insert(name)
            runUmount(path: mountRoot.appendingPathComponent(name).path, force: false)
        }
        // Give rclone a moment to flush and exit cleanly, then force what's left.
        let deadline = Date().addingTimeInterval(8)
        while processes.values.contains(where: { $0.isRunning }) && Date() < deadline {
            usleep(100_000)
        }
        for (name, process) in processes {
            let point = mountRoot.appendingPathComponent(name).path
            if Self.isMounted(path: point) { forceUnmount(path: point) }
            if process.isRunning { process.terminate() }
        }
        processes.removeAll()
    }

    private func processDidExit(remote: String, status: Int32) {
        let wasExpected = expectedExits.remove(remote) != nil
        processes[remote] = nil
        guard !wasExpected else { return }
        // Unexpected death (crash, network failure, killed externally).
        let log = logDirectory.appendingPathComponent("\(remote).log")
        let hint = Self.lastLogLine(of: log)
        states[remote] = .failed(hint ?? "rclone exited unexpectedly (status \(status))")
        let point = mountRoot.appendingPathComponent(remote).path
        if Self.isMounted(path: point) { forceUnmount(path: point) }
    }

    // MARK: - Mount table helpers

    /// True if `path` is currently a mount point (per statfs of the mount table).
    /// Paths are canonicalized: the mount table stores e.g. /private/var/…
    /// while callers may pass /var/… (a symlink).
    public nonisolated static func isMounted(path: String) -> Bool {
        let target = canonicalize(path)
        var count: Int32 = 0
        var mounts: UnsafeMutablePointer<statfs>?
        count = getmntinfo(&mounts, MNT_NOWAIT)
        guard count > 0, let mounts else { return false }
        for i in 0..<Int(count) {
            let dir = withUnsafeBytes(of: mounts[i].f_mntonname) { raw in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            if dir == target { return true }
        }
        return false
    }

    /// Resolve symlinks (e.g. /var → /private/var) without requiring the
    /// full path to exist as seen by realpath's strict mode.
    private nonisolated static func canonicalize(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buffer) != nil {
            return String(cString: buffer)
        }
        return path
    }

    private nonisolated func runUmount(path: String, force: Bool) {
        let umount = Process()
        umount.executableURL = URL(fileURLWithPath: "/sbin/umount")
        umount.arguments = force ? ["-f", path] : [path]
        umount.standardError = FileHandle.nullDevice
        try? umount.run()
        umount.waitUntilExit()
    }

    private nonisolated func forceUnmount(path: String) {
        runUmount(path: path, force: true)
    }

    private nonisolated static func lastLogLine(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
            .components(separatedBy: .newlines)
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
