import Foundation

/// hdiutil wrapper for the APFS sparsebundles Time Machine backs up into.
public enum SparseBundle {

    /// Create a case-sensitive APFS sparsebundle. `sizeGB` is the quota Time
    /// Machine will see. An optional passphrase enables AES-256 encryption
    /// (recommended: source disks are usually FileVault-encrypted, and macOS
    /// warns when backing them up to an unencrypted destination).
    public static func create(at url: URL, volumeName: String, sizeGB: Int,
                              passphrase: String? = nil) throws {
        var args = ["create", "-size", "\(sizeGB)g", "-type", "SPARSEBUNDLE",
                    "-fs", "Case-sensitive APFS", "-volname", volumeName]
        if passphrase != nil {
            args += ["-encryption", "AES-256", "-stdinpass"]
        }
        args.append(url.path)
        try runHdiutil(args, stdin: passphrase)
    }

    /// Attach and return the mounted volume path (/Volumes/<volname>).
    @discardableResult
    public static func attach(_ url: URL, passphrase: String? = nil) throws -> String {
        var args = ["attach"]
        if passphrase != nil { args.append("-stdinpass") }
        args.append(url.path)
        let output = try runHdiutil(args, stdin: passphrase)
        // Last column of the last line is the mount point.
        for line in output.components(separatedBy: .newlines).reversed() {
            if let range = line.range(of: "/Volumes/") {
                return String(line[range.lowerBound...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        throw MountGateError.rcloneFailed("hdiutil attach: no mount point in output")
    }

    public static func detach(volumePath: String, force: Bool = false) throws {
        var args = ["detach", volumePath]
        if force { args.append("-force") }
        try runHdiutil(args, stdin: nil)
    }

    public static func isAttached(volumePath: String) -> Bool {
        FileManager.default.fileExists(atPath: volumePath)
            && MountController.isMounted(path: volumePath)
    }

    @discardableResult
    private static func runHdiutil(_ args: [String], stdin: String?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        if let stdin {
            let inPipe = Pipe()
            process.standardInput = inPipe
            try process.run()
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            inPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8) ?? "hdiutil failed"
            throw MountGateError.rcloneFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
