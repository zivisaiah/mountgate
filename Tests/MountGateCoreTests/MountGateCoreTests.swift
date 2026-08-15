import Testing
import Foundation
@testable import MountGateCore

@Suite struct ModelTests {
    @Test func remoteSpec() {
        #expect(Remote(name: "mys3").spec == "mys3:")
        #expect(Remote(name: "mys3").id == "mys3")
    }

    @Test func mountStateBusy() {
        #expect(MountState.mounting.isBusy)
        #expect(MountState.unmounting.isBusy)
        #expect(!MountState.mounted.isBusy)
        #expect(!MountState.unmounted.isBusy)
        #expect(!MountState.failed("x").isBusy)
    }
}

@Suite struct MountTableTests {
    @Test func isMountedOnKnownPaths() {
        // "/" is always a mount point; a random temp subdirectory is not.
        #expect(MountController.isMounted(path: "/"))
        #expect(!MountController.isMounted(path: NSTemporaryDirectory()))
    }
}

@Suite struct EngineTests {
    @Test func locateHonorsEnvironmentOverride() throws {
        // /bin/ls exists and is executable — good enough for locating logic.
        // Injected env avoids racing parallel tests via global setenv.
        let engine = try RcloneEngine.locate(environment: ["MOUNTGATE_RCLONE": "/bin/ls"])
        #expect(engine.binaryURL.path == "/bin/ls")
    }

    @Test func versionRunsAgainstRealBinary() throws {
        // Exercises run() against the vendored rclone if present; skip otherwise.
        guard let engine = try? RcloneEngine.locate(),
              engine.binaryURL.lastPathComponent == "rclone" else { return }
        let version = try engine.version()
        #expect(version.contains("rclone v"))
    }
}
