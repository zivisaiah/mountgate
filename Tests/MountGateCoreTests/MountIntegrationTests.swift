import Testing
import Foundation
@testable import MountGateCore

private var hasVendoredRclone: Bool {
    guard let engine = try? RcloneEngine.locate() else { return false }
    return engine.binaryURL.lastPathComponent == "rclone"
}

/// End-to-end mount lifecycle against rclone's in-memory backend.
/// Requires the vendored rclone binary (scripts/fetch-rclone.sh); skipped otherwise.
@Suite(.serialized) struct MountIntegrationTests {

    @MainActor
    private func makeController() throws -> (MountController, URL) {
        let engine = try RcloneEngine.locate()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mountgate-test-\(UUID().uuidString)")
        let controller = MountController(
            engine: engine,
            mountRoot: tmp.appendingPathComponent("mounts"),
            logDirectory: tmp.appendingPathComponent("logs"))
        return (controller, tmp)
    }

    @Test(.enabled(if: hasVendoredRclone))
    @MainActor func mountWriteReadUnmount() async throws {
        let (controller, tmp) = try makeController()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // ":memory" + trailing colon from Remote.spec = the ":memory:" backend.
        let remote = Remote(name: ":memory")
        await controller.mount(remote)
        #expect(controller.state(of: remote) == .mounted)

        let point = controller.mountPoint(for: remote)
        #expect(MountController.isMounted(path: point.path))

        let file = point.appendingPathComponent("hello.txt")
        try "hello mountgate".write(to: file, atomically: true, encoding: .utf8)
        #expect(try String(contentsOf: file, encoding: .utf8) == "hello mountgate")

        await controller.unmount(remote)
        #expect(controller.state(of: remote) == .unmounted)
        #expect(!MountController.isMounted(path: point.path))
    }

    @Test(.enabled(if: hasVendoredRclone))
    @MainActor func mountFailureSurfacesError() async throws {
        let (controller, tmp) = try makeController()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // A remote that doesn't exist in any config must fail, not hang.
        let bogus = Remote(name: "definitely-not-configured-\(Int.random(in: 0..<99999))")
        await controller.mount(bogus)
        guard case .failed = controller.state(of: bogus) else {
            Issue.record("Expected .failed, got \(controller.state(of: bogus))")
            return
        }
    }
}
