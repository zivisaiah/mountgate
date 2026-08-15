import Foundation

/// A configured rclone remote that can be mounted.
public struct Remote: Identifiable, Hashable, Sendable {
    /// rclone remote name without the trailing colon, e.g. "mys3".
    public let name: String

    public var id: String { name }

    /// The rclone remote spec used on the command line, e.g. "mys3:".
    public var spec: String { name + ":" }

    public init(name: String) {
        self.name = name
    }
}

/// Lifecycle state of a single mount.
public enum MountState: Equatable, Sendable {
    case unmounted
    case mounting
    case mounted
    case unmounting
    case failed(String)

    public var isBusy: Bool {
        self == .mounting || self == .unmounting
    }
}

/// Errors surfaced by the mounting machinery.
public enum MountGateError: LocalizedError {
    case rcloneNotFound
    case rcloneFailed(String)
    case mountPointUnavailable(String)
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .rcloneNotFound:
            return "The bundled rclone engine could not be found."
        case .rcloneFailed(let detail):
            return "rclone failed: \(detail)"
        case .mountPointUnavailable(let path):
            return "Mount point unavailable: \(path)"
        case .timeout(let what):
            return "Timed out waiting for \(what)."
        }
    }
}
