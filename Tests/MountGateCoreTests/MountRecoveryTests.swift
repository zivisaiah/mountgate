import Testing
import Foundation
@testable import MountGateCore

private var hasVendoredRclone: Bool {
    guard let engine = try? RcloneEngine.locate() else { return false }
    return engine.binaryURL.lastPathComponent == "rclone"
}

/// M3 behaviors: crash auto-remount and stale-mount recovery.
@Suite(.serialized) struct MountRecoveryTests {

    @MainActor
    private func makeController() throws -> (MountController, URL) {
        let engine = try RcloneEngine.locate()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mountgate-rec-\(UUID().uuidString)")
        let controller = MountController(
            engine: engine,
            mountRoot: tmp.appendingPathComponent("mounts"),
            logDirectory: tmp.appendingPathComponent("logs"))
        return (controller, tmp)
    }

    /// SIGKILL the rclone child; the controller must notice and remount.
    @Test(.enabled(if: hasVendoredRclone), .timeLimit(.minutes(1)))
    @MainActor func autoRemountAfterKill() async throws {
        let (controller, tmp) = try makeController()
        defer {
            controller.unmountAllForShutdown()
            try? FileManager.default.removeItem(at: tmp)
        }

        let remote = Remote(name: ":memory")
        await controller.mount(remote)
        #expect(controller.state(of: remote) == .mounted)

        // Kill the rclone process serving this mount point from outside.
        let point = controller.mountPoint(for: remote).path
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-9", "-f", "nfsmount .* \(point)"]
        try pkill.run()
        pkill.waitUntilExit()
        #expect(pkill.terminationStatus == 0, "pkill should find the rclone child")

        // Backoff for attempt 1 is 1s; allow generous time for remount.
        var remounted = false
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(500))
            if controller.state(of: remote) == .mounted {
                remounted = true
                break
            }
        }
        #expect(remounted, "controller should have auto-remounted after SIGKILL")

        await controller.unmount(remote)
        #expect(controller.state(of: remote) == .unmounted)
    }

    /// A mount left behind by a dead controller must be cleaned up on startup.
    @Test(.enabled(if: hasVendoredRclone), .timeLimit(.minutes(1)))
    @MainActor func staleMountRecovery() async throws {
        let engine = try RcloneEngine.locate()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mountgate-stale-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let root = tmp.appendingPathComponent("mounts")
        let stale = root.appendingPathComponent("stale")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)

        // Simulate a previous app run: raw rclone mount, not owned by anyone.
        let orphan = Process()
        orphan.executableURL = engine.binaryURL
        orphan.arguments = ["nfsmount", ":memory:", stale.path,
                            "-o", "nolocks", "-o", "locallocks"]
        orphan.standardOutput = FileHandle.nullDevice
        orphan.standardError = FileHandle.nullDevice
        try orphan.run()
        var appeared = false
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            if MountController.isMounted(path: stale.path) { appeared = true; break }
        }
        #expect(appeared, "orphan mount should come up")

        // A fresh controller over the same root must clean it up.
        let controller = MountController(
            engine: engine,
            mountRoot: root,
            logDirectory: tmp.appendingPathComponent("logs"))
        controller.recoverStaleMounts()
        var cleaned = false
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            if !MountController.isMounted(path: stale.path) { cleaned = true; break }
        }
        #expect(cleaned, "stale mount should be force-unmounted")
        if orphan.isRunning { orphan.terminate() }
    }
}
