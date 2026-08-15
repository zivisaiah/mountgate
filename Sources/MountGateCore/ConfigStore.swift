import Foundation

/// Programmatic management of MountGate's rclone config (remotes = accounts).
public struct ConfigStore: Sendable {
    public let engine: RcloneEngine

    public init(engine: RcloneEngine) {
        self.engine = engine
        if let configURL = engine.configURL {
            let dir = configURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Credentials live here (rclone-obscured, not encrypted) — keep it private.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
    }

    public func remotes() throws -> [Remote] {
        try engine.listRemotes()
    }

    /// name → (type + options), parsed from `rclone config dump`.
    public func dump() throws -> [String: [String: String]] {
        let json = try engine.run(["config", "dump"])
        guard let data = json.data(using: .utf8),
              let raw = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            return [:]
        }
        return raw.mapValues { $0.compactMapValues { "\($0)" } }
    }

    /// Create a remote. `options` are backend parameters (access_key_id, …).
    /// Password-typed values may be passed in plaintext; `--obscure` makes
    /// rclone store them obscured.
    public func createRemote(name: String, type: String, options: [String: String]) throws {
        var args = ["config", "create", name, type, "--non-interactive", "--obscure"]
        for (key, value) in options.sorted(by: { $0.key < $1.key }) {
            args += [key, value]
        }
        try engine.run(args)
        try restrictConfigPermissions()
    }

    public func updateRemote(name: String, options: [String: String]) throws {
        var args = ["config", "update", name, "--non-interactive", "--obscure"]
        for (key, value) in options.sorted(by: { $0.key < $1.key }) {
            args += [key, value]
        }
        try engine.run(args)
    }

    public func deleteRemote(name: String) throws {
        try engine.run(["config", "delete", name])
    }

    /// Quick reachability probe for an account (cheap listing, 10s timeout).
    public func verifyRemote(name: String) -> Result<Void, MountGateError> {
        do {
            _ = try engine.run(["lsd", "--max-depth", "1", "--contimeout", "10s",
                                "--timeout", "10s", "--retries", "1", name + ":"])
            return .success(())
        } catch let error as MountGateError {
            return .failure(error)
        } catch {
            return .failure(.rcloneFailed(error.localizedDescription))
        }
    }

    private func restrictConfigPermissions() throws {
        guard let configURL = engine.configURL,
              FileManager.default.fileExists(atPath: configURL.path) else { return }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }
}
