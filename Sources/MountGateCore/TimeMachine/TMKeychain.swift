import Foundation

/// Stores sparsebundle encryption passphrases in the user's login Keychain
/// (like macOS itself does for Time Machine disk passwords), so encrypted
/// backup volumes re-attach automatically after reboots.
public enum TMKeychain {
    static let service = "io.github.zivisaiah.mountgate.tm"

    public static func savePassphrase(_ passphrase: String, destinationName: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        // -U updates an existing item instead of failing.
        process.arguments = ["add-generic-password",
                             "-a", destinationName,
                             "-s", service,
                             "-l", "MountGate backup “\(destinationName)”",
                             "-w", passphrase,
                             "-U"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MountGateError.rcloneFailed("could not store passphrase in Keychain")
        }
    }

    public static func loadPassphrase(destinationName: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password",
                             "-a", destinationName,
                             "-s", service,
                             "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let passphrase = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .newlines)
        return (passphrase?.isEmpty ?? true) ? nil : passphrase
    }

    public static func deletePassphrase(destinationName: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["delete-generic-password",
                             "-a", destinationName,
                             "-s", service]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
