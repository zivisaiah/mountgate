import Testing
import Foundation
@testable import MountGateCore

private var hasVendoredRclone: Bool {
    guard let engine = try? RcloneEngine.locate() else { return false }
    return engine.binaryURL.lastPathComponent == "rclone"
}

@Suite struct ConfigStoreTests {

    private func makeStore() throws -> (ConfigStore, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mountgate-cfg-\(UUID().uuidString)")
        let configURL = tmp.appendingPathComponent("rclone.conf")
        let engine = try RcloneEngine.locate().withConfig(configURL)
        return (ConfigStore(engine: engine), tmp)
    }

    @Test(.enabled(if: hasVendoredRclone))
    func createListDeleteRoundTrip() throws {
        let (store, tmp) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try store.createRemote(name: "tests3", type: "s3", options: [
            "provider": "Other",
            "access_key_id": "AKIAFAKE",
            "secret_access_key": "fakesecret",
            "endpoint": "https://s3.example.com",
        ])
        #expect(try store.remotes().map(\.name) == ["tests3"])

        let dump = try store.dump()
        #expect(dump["tests3"]?["type"] == "s3")
        #expect(dump["tests3"]?["endpoint"] == "https://s3.example.com")

        try store.updateRemote(name: "tests3", options: ["region": "eu-central-1"])
        #expect(try store.dump()["tests3"]?["region"] == "eu-central-1")

        try store.deleteRemote(name: "tests3")
        #expect(try store.remotes().isEmpty)
    }

    @Test(.enabled(if: hasVendoredRclone))
    func passwordsAreObscuredInConfigFile() throws {
        let (store, tmp) = try makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try store.createRemote(name: "box", type: "sftp", options: [
            "host": "example.com",
            "user": "ziv",
            "pass": "supersecret123",
        ])
        let content = try String(contentsOf: tmp.appendingPathComponent("rclone.conf"),
                                 encoding: .utf8)
        #expect(!content.contains("supersecret123"),
                "plaintext password must not appear in the config file")

        // File must be private.
        let attrs = try FileManager.default.attributesOfItem(
            atPath: tmp.appendingPathComponent("rclone.conf").path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
    }

    @Test func tokenExtraction() {
        let sample = """
        2026/08/15 12:00:00 NOTICE: Waiting for code...
        Paste the following into your remote machine --->
        {"access_token":"ya29.xxx","token_type":"Bearer","expiry":"2026-08-15T13:00:00Z"}
        <---End paste
        """
        let token = AuthFlow.extractToken(from: sample)
        #expect(token?.contains("ya29.xxx") == true)
        #expect(AuthFlow.extractToken(from: "no json here") == nil)
    }
}
