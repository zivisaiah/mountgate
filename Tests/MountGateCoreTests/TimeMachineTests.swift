import Testing
import Foundation
@testable import MountGateCore

private var hasVendoredRclone: Bool {
    guard let engine = try? RcloneEngine.locate() else { return false }
    return engine.binaryURL.lastPathComponent == "rclone"
}

@Suite struct SparseBundleTests {

    @Test func createAttachDetachRoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mg-sb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let volname = "MGTest-\(Int.random(in: 1000..<9999))"
        let bundle = tmp.appendingPathComponent("test.sparsebundle")
        try SparseBundle.create(at: bundle, volumeName: volname, sizeGB: 1)
        #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Info.plist").path))

        let volume = try SparseBundle.attach(bundle)
        #expect(volume == "/Volumes/\(volname)")
        #expect(SparseBundle.isAttached(volumePath: volume))

        try "probe".write(to: URL(fileURLWithPath: volume).appendingPathComponent("probe.txt"),
                          atomically: true, encoding: .utf8)
        try SparseBundle.detach(volumePath: volume)
        #expect(!SparseBundle.isAttached(volumePath: volume))
    }

    @Test func encryptedBundleRequiresPassphrase() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mg-sbe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let volname = "MGCrypt-\(Int.random(in: 1000..<9999))"
        let bundle = tmp.appendingPathComponent("enc.sparsebundle")
        try SparseBundle.create(at: bundle, volumeName: volname, sizeGB: 1,
                                passphrase: "spike-test-passphrase")
        let volume = try SparseBundle.attach(bundle, passphrase: "spike-test-passphrase")
        #expect(SparseBundle.isAttached(volumePath: volume))
        try SparseBundle.detach(volumePath: volume)
    }
}

@Suite struct TMDestinationTests {

    @Test func storeRoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mg-tmstore-\(UUID().uuidString)/TMDestinations.json")
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }
        let store = TMDestinationStore(fileURL: tmp)
        #expect(store.load().isEmpty)

        let destination = TMDestination(
            name: "Test Backup", accountName: "mys3",
            remotePath: "mountgate-tm/Test Backup.sparsebundle",
            bundleURL: URL(fileURLWithPath: "/tmp/x.sparsebundle"),
            sizeGB: 500, encrypted: true, lastSync: Date(timeIntervalSince1970: 1000))
        try store.save([destination])
        let loaded = store.load()
        #expect(loaded == [destination])
        #expect(loaded[0].remoteSpec == "mys3:mountgate-tm/Test Backup.sparsebundle")
        #expect(loaded[0].volumePath == "/Volumes/Test Backup")
    }

    @Test func destinationInfoParsing() {
        let sample = """
        > ==================================================
        Name          : My Passport
        Kind          : Local
        ID            : 27E2D119-ABE6-4759-B719-26A3C104D80F
        ====================================================
        Name          : Backup Two
        Kind          : Network
        URL           : smb://example/share
        ID            : EAB3DEBE-3AF3-4C21-9C0E-960F67085381
        """
        let ids = PrivilegedOps.parseDestinationInfo(sample)
        #expect(ids["My Passport"] == "27E2D119-ABE6-4759-B719-26A3C104D80F")
        #expect(ids["Backup Two"] == "EAB3DEBE-3AF3-4C21-9C0E-960F67085381")
    }
}

/// Full staged pipeline against a local "cloud": create destination,
/// write into the volume, sync, verify remote copy, restore.
@Suite(.serialized) struct TMPipelineTests {

    @Test(.enabled(if: hasVendoredRclone), .timeLimit(.minutes(3)))
    @MainActor func stagedSyncAndRestore() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mg-tmpipe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let engine = try RcloneEngine.locate()
        let store = TMDestinationStore(fileURL: tmp.appendingPathComponent("dest.json"))
        let tm = TMController(engine: engine, store: store)

        // Cloud stand-in + destination whose bundle lives in our tmp dir.
        let cloud = tmp.appendingPathComponent("cloud")
        let volname = "MGPipe-\(Int.random(in: 1000..<9999))"
        let bundleURL = tmp.appendingPathComponent("\(volname).sparsebundle")
        try SparseBundle.create(at: bundleURL, volumeName: volname, sizeGB: 1)
        let volume = try SparseBundle.attach(bundleURL)
        var destination = TMDestination(
            name: volname, accountName: ":local",
            remotePath: "\(cloud.path)/\(volname).sparsebundle",
            bundleURL: bundleURL, sizeGB: 1, encrypted: false)

        try "backup payload".write(
            to: URL(fileURLWithPath: volume).appendingPathComponent("payload.txt"),
            atomically: true, encoding: .utf8)
        try SparseBundle.detach(volumePath: volume)

        // Inject and sync.
        tm.setDestinationsForTesting([destination])
        tm.requestSync(destination)
        var synced = false
        for _ in 0..<120 {
            try? await Task.sleep(for: .milliseconds(500))
            if tm.syncState(of: destination) == .idle,
               tm.destinations.first?.lastSync != nil { synced = true; break }
            if case .failed = tm.syncState(of: destination) { break }
        }
        #expect(synced, "sync should complete: \(tm.syncState(of: destination))")
        #expect(FileManager.default.fileExists(
            atPath: cloud.appendingPathComponent("\(volname).sparsebundle/Info.plist").path))

        // Restore from the "cloud" and check the payload survived.
        destination = tm.destinations[0]
        let restoreDir = tmp.appendingPathComponent("restore")
        try FileManager.default.createDirectory(at: restoreDir, withIntermediateDirectories: true)
        let restoredVolume = try await tm.restore(destination, to: restoreDir)
        defer { try? SparseBundle.detach(volumePath: restoredVolume, force: true) }
        let payload = try String(
            contentsOf: URL(fileURLWithPath: restoredVolume).appendingPathComponent("payload.txt"),
            encoding: .utf8)
        #expect(payload == "backup payload")
    }
}
