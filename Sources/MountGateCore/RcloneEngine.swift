import Foundation

/// Locates and runs the rclone binary that powers all storage operations.
///
/// Lookup order:
///   1. `MOUNTGATE_RCLONE` environment variable (tests / development override)
///   2. The app bundle's Resources directory (production)
///   3. `Vendor/rclone` relative to the working directory (swift run during development)
///   4. Homebrew / system locations (developer convenience fallback)
public struct RcloneEngine: Sendable {
    public let binaryURL: URL

    public init(binaryURL: URL) {
        self.binaryURL = binaryURL
    }

    /// Discover the rclone binary, or throw `MountGateError.rcloneNotFound`.
    /// `environment` is injectable for tests; defaults to the process environment.
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> RcloneEngine {
        let fm = FileManager.default
        var candidates: [URL] = []

        if let override = environment["MOUNTGATE_RCLONE"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("rclone"))
        }
        candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("Vendor/rclone"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/rclone"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/rclone"))

        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return RcloneEngine(binaryURL: url)
        }
        throw MountGateError.rcloneNotFound
    }

    /// Run an rclone subcommand to completion and return trimmed stdout.
    /// Throws `MountGateError.rcloneFailed` with stderr on non-zero exit.
    @discardableResult
    public func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        // Drain pipes before waiting to avoid deadlock on large output.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw MountGateError.rcloneFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (String(data: outData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// rclone's own version string, e.g. "rclone v1.71.0".
    public func version() throws -> String {
        let output = try run(["version"])
        return output.components(separatedBy: .newlines).first ?? output
    }

    /// Names of remotes configured in the active rclone config.
    public func listRemotes() throws -> [Remote] {
        let output = try run(["listremotes"])
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasSuffix(":") }
            .map { Remote(name: String($0.dropLast())) }
    }
}
