import Foundation

/// A MountGate-managed Time Machine destination (Staged mode):
/// Time Machine backs up into a local sparsebundle, and MountGate syncs the
/// changed band files to a cloud remote after each backup.
public struct TMDestination: Codable, Identifiable, Hashable, Sendable {
    public var id: String { name }

    /// Display name; also the APFS volume name (e.g. "MountGate Backup").
    public let name: String
    /// rclone remote (account) name that receives the bundle.
    public let accountName: String
    /// Path within the remote, e.g. "mountgate-tm/MacBook.sparsebundle".
    public let remotePath: String
    /// Local staging sparsebundle location.
    public let bundleURL: URL
    /// Quota (GB) Time Machine sees.
    public let sizeGB: Int
    public let encrypted: Bool
    /// Last successful cloud sync, nil if never synced.
    public var lastSync: Date?

    public init(name: String, accountName: String, remotePath: String,
                bundleURL: URL, sizeGB: Int, encrypted: Bool, lastSync: Date? = nil) {
        self.name = name
        self.accountName = accountName
        self.remotePath = remotePath
        self.bundleURL = bundleURL
        self.sizeGB = sizeGB
        self.encrypted = encrypted
        self.lastSync = lastSync
    }

    /// Where the attached volume lives.
    public var volumePath: String { "/Volumes/\(name)" }
    /// Full rclone destination spec.
    public var remoteSpec: String { "\(accountName):\(remotePath)" }
}

/// JSON-file persistence for TM destinations.
public struct TMDestinationStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MountGate/TMDestinations.json")
    }

    public func load() -> [TMDestination] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([TMDestination].self, from: data)) ?? []
    }

    public func save(_ destinations: [TMDestination]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(destinations).write(to: fileURL, options: .atomic)
    }
}
