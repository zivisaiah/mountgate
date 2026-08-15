import Foundation

/// The few Time Machine operations that need admin rights (and Full Disk
/// Access). Uses osascript's "with administrator privileges" so macOS shows
/// its standard credential dialog — no helper daemon needed.
public enum PrivilegedOps {

    /// Does this process have Full Disk Access? `tmutil setdestination`
    /// silently requires it (verified on macOS 26).
    public static func hasFullDiskAccess() -> Bool {
        // Reading the user TCC database is only possible with FDA.
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        return FileManager.default.isReadableFile(atPath: probe.path)
    }

    /// Open System Settings on the Full Disk Access pane.
    public static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try? process.run()
    }

    /// `sudo tmutil setdestination -a <volume>` via the admin auth dialog.
    public static func addTMDestination(volumePath: String) throws {
        try runPrivileged("/usr/bin/tmutil setdestination -a " + shellQuote(volumePath))
    }

    /// `sudo tmutil removedestination <id>`.
    public static func removeTMDestination(id: String) throws {
        try runPrivileged("/usr/bin/tmutil removedestination " + shellQuote(id))
    }

    /// Destination IDs by name, parsed from `tmutil destinationinfo` (no sudo).
    public static func destinationIDs() -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["destinationinfo"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [:] }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return parseDestinationInfo(output)
    }

    static func parseDestinationInfo(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentName: String?
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            if parts[0].hasSuffix("Name") { currentName = parts[1] }
            if parts[0].hasSuffix("ID"), let name = currentName {
                result[name] = parts[1]
                currentName = nil
            }
        }
        return result
    }

    private static func runPrivileged(_ command: String) throws {
        let script = "do shell script \"\(command.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8) ?? "privileged command failed"
            throw MountGateError.rcloneFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
