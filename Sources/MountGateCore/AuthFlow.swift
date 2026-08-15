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
    /// finishes or `timeout` elapses. `onAuthURL` receives the sign-in link
    /// rclone prints, so the UI can offer it for manual/private-window use
    /// (Google's consent page sometimes 400s in browsers with many accounts).
    public func authorize(rcloneType: String,
                          clientID: String? = nil,
                          clientSecret: String? = nil,
                          timeout: TimeInterval = 300,
                          onAuthURL: (@Sendable (String) -> Void)? = nil) async throws -> String {
        var args = ["authorize", rcloneType]
        if let clientID, !clientID.isEmpty {
            args.append(clientID)
            if let clientSecret, !clientSecret.isEmpty { args.append(clientSecret) }
        }
        // The browser is opened by rclone; we also watch stderr for the URL.
        let process = Process()
        process.executableURL = engine.binaryURL
        process.arguments = engine.arguments(args)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stderrBuffer = LockedBuffer()
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            let text = stderrBuffer.appendAndSnapshot(chunk)
            if let onAuthURL, let url = Self.extractAuthURL(from: text) {
                onAuthURL(url)
                stderr.fileHandleForReading.readabilityHandler = nil
            }
        }

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
        stderr.fileHandleForReading.readabilityHandler = nil
        guard process.terminationStatus == 0 else {
            throw MountGateError.timeout("browser sign-in")
        }
        let output = String(data: data, encoding: .utf8) ?? ""
        guard let token = Self.extractToken(from: output) else {
            throw MountGateError.rcloneFailed("no token in authorize output")
        }
        return token
    }

    private final class LockedBuffer: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()
        func appendAndSnapshot(_ chunk: Data) -> String {
            lock.lock()
            defer { lock.unlock() }
            data.append(chunk)
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    /// The localhost sign-in link rclone prints, e.g.
    /// "…go to the following link: http://127.0.0.1:53682/auth?state=XYZ".
    static func extractAuthURL(from output: String) -> String? {
        guard let range = output.range(of: #"http://127\.0\.0\.1:\d+/auth\?state=[A-Za-z0-9_-]+"#,
                                       options: .regularExpression) else { return nil }
        return String(output[range])
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
