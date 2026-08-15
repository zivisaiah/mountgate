import Foundation

/// Runs rclone's built-in OAuth flow: `rclone authorize <type>` starts a
/// localhost redirect server, opens the user's browser, and prints the
/// resulting token JSON. The returned token is passed to `config create`.
public struct AuthFlow: Sendable {
    public let engine: RcloneEngine

    public init(engine: RcloneEngine) {
        self.engine = engine
    }

    /// Perform the browser OAuth dance. Blocks (async) until the user
    /// finishes or `timeout` elapses.
    public func authorize(rcloneType: String,
                          clientID: String? = nil,
                          clientSecret: String? = nil,
                          timeout: TimeInterval = 300) async throws -> String {
        var args = ["authorize", rcloneType]
        if let clientID, !clientID.isEmpty {
            args.append(clientID)
            if let clientSecret, !clientSecret.isEmpty { args.append(clientSecret) }
        }
        // --auth-no-open-browser? No — we want the browser opened for the user.
        let process = Process()
        process.executableURL = engine.binaryURL
        process.arguments = engine.arguments(args)
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try process.run()

        let reader = Task.detached { () -> Data in
            stdout.fileHandleForReading.readDataToEndOfFile()
        }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if process.isRunning { process.terminate() }
        }
        defer { watchdog.cancel() }

        let data = await reader.value
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MountGateError.timeout("browser sign-in")
        }
        let output = String(data: data, encoding: .utf8) ?? ""
        guard let token = Self.extractToken(from: output) else {
            throw MountGateError.rcloneFailed("no token in authorize output")
        }
        return token
    }

    /// `rclone authorize` wraps the token JSON in paste markers; find the
    /// first line that parses as a JSON object.
    static func extractToken(from output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
                  let data = trimmed.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) != nil else { continue }
            return trimmed
        }
        return nil
    }
}
