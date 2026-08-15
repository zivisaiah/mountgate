import Foundation

/// One input field of an account-setup form.
public struct ProviderField: Identifiable, Sendable {
    /// rclone backend option key, e.g. "access_key_id".
    public let key: String
    public let label: String
    public let secure: Bool
    public let required: Bool
    public let placeholder: String

    public var id: String { key }

    public init(key: String, label: String, secure: Bool = false,
                required: Bool = true, placeholder: String = "") {
        self.key = key
        self.label = label
        self.secure = secure
        self.required = required
        self.placeholder = placeholder
    }
}

/// Endpoint preset for S3-compatible services.
public struct S3Preset: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    /// Value for rclone's s3 `provider` option.
    public let provider: String
    /// Endpoint hint; empty = AWS default endpoints.
    public let endpointPlaceholder: String

    public init(id: String, label: String, provider: String, endpointPlaceholder: String) {
        self.id = id
        self.label = label
        self.provider = provider
        self.endpointPlaceholder = endpointPlaceholder
    }
}

/// A cloud storage provider MountGate can configure.
public struct Provider: Identifiable, Sendable {
    public let id: String
    public let label: String
    /// rclone backend type ("s3", "sftp", "webdav", "drive", "google cloud storage").
    public let rcloneType: String
    public let fields: [ProviderField]
    /// Fixed options merged into every remote of this provider.
    public let constantOptions: [String: String]
    public let usesOAuth: Bool

    public init(id: String, label: String, rcloneType: String,
                fields: [ProviderField], constantOptions: [String: String] = [:],
                usesOAuth: Bool = false) {
        self.id = id
        self.label = label
        self.rcloneType = rcloneType
        self.fields = fields
        self.constantOptions = constantOptions
        self.usesOAuth = usesOAuth
    }
}

public enum ProviderCatalog {
    public static let s3Presets: [S3Preset] = [
        .init(id: "aws", label: "Amazon S3", provider: "AWS",
              endpointPlaceholder: ""),
        .init(id: "r2", label: "Cloudflare R2", provider: "Cloudflare",
              endpointPlaceholder: "https://<accountid>.r2.cloudflarestorage.com"),
        .init(id: "b2", label: "Backblaze B2 (S3 API)", provider: "Other",
              endpointPlaceholder: "https://s3.<region>.backblazeb2.com"),
        .init(id: "hetzner", label: "Hetzner Object Storage", provider: "Other",
              endpointPlaceholder: "https://<location>.your-objectstorage.com"),
        .init(id: "minio", label: "MinIO", provider: "Minio",
              endpointPlaceholder: "http://localhost:9000"),
        .init(id: "other", label: "Other S3-compatible", provider: "Other",
              endpointPlaceholder: "https://s3.example.com"),
    ]

    public static let s3 = Provider(
        id: "s3", label: "S3-compatible", rcloneType: "s3",
        fields: [
            .init(key: "access_key_id", label: "Access Key ID"),
            .init(key: "secret_access_key", label: "Secret Access Key", secure: true),
            .init(key: "endpoint", label: "Endpoint", required: false),
            .init(key: "region", label: "Region", required: false, placeholder: "us-east-1"),
        ])

    public static let sftp = Provider(
        id: "sftp", label: "SFTP (incl. Hetzner Storage Box)", rcloneType: "sftp",
        fields: [
            .init(key: "host", label: "Host", placeholder: "u123456.your-storagebox.de"),
            .init(key: "user", label: "Username"),
            .init(key: "port", label: "Port", required: false, placeholder: "22"),
            .init(key: "pass", label: "Password", secure: true, required: false),
            .init(key: "key_file", label: "SSH key file path", required: false,
                  placeholder: "~/.ssh/id_ed25519"),
        ])

    public static let webdav = Provider(
        id: "webdav", label: "WebDAV", rcloneType: "webdav",
        fields: [
            .init(key: "url", label: "URL", placeholder: "https://dav.example.com/remote.php/webdav/"),
            .init(key: "user", label: "Username", required: false),
            .init(key: "pass", label: "Password", secure: true, required: false),
        ])

    public static let googleDrive = Provider(
        id: "drive", label: "Google Drive", rcloneType: "drive",
        fields: [
            .init(key: "client_id", label: "OAuth Client ID (optional)", required: false),
            .init(key: "client_secret", label: "OAuth Client Secret (optional)",
                  secure: true, required: false),
        ],
        constantOptions: ["scope": "drive"],
        usesOAuth: true)

    public static let gcs = Provider(
        id: "gcs", label: "Google Cloud Storage", rcloneType: "google cloud storage",
        fields: [
            .init(key: "service_account_file", label: "Service account JSON path",
                  required: false, placeholder: "leave empty to sign in with Google"),
            .init(key: "project_number", label: "Project number", required: false),
        ],
        usesOAuth: true)

    public static let all: [Provider] = [s3, sftp, webdav, googleDrive, gcs]

    public static func provider(id: String) -> Provider? {
        all.first { $0.id == id }
    }
}
