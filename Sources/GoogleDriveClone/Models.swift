import Foundation

struct RcloneRemote: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String

    var displayName: String {
        name.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    }
}

struct RcloneConfigEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

struct RcloneProfileDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var entries: [RcloneConfigEntry]

    init(id: UUID = UUID(), name: String, entries: [RcloneConfigEntry]) {
        self.id = id
        self.name = name
        self.entries = entries
    }
}

struct RcloneConfigDocument: Hashable, Sendable {
    var path: String
    var profiles: [RcloneProfileDraft]
}

struct RemoteFolder: Identifiable, Hashable, Sendable {
    var id: String { path }
    let name: String
    let path: String
}

struct RemoteItem: Identifiable, Hashable, Sendable {
    var id: String { "\(isDirectory ? "d" : "f"):\(path)" }
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?
}

struct DroppedUploadItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    var url: URL
    var isDirectory: Bool

    var name: String {
        url.lastPathComponent
    }

    var path: String {
        url.path
    }
}

struct AccountUsage: Identifiable, Hashable, Codable, Sendable {
    static let dailyLimitBytes: Int64 = 750_000_000_000

    var id: String { remoteName }
    let remoteName: String
    var dateKey: String
    var bytesTransferred: Int64

    var remainingBytes: Int64 {
        max(0, Self.dailyLimitBytes - bytesTransferred)
    }

    var fractionUsed: Double {
        min(1, Double(bytesTransferred) / Double(Self.dailyLimitBytes))
    }

    var isAtCapacity: Bool {
        remainingBytes <= 0
    }
}

enum SyncMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case copy
    case sync
    case bisync

    var id: String { rawValue }

    var label: String {
        switch self {
        case .copy: "Copy"
        case .sync: "Mirror"
        case .bisync: "Two-way"
        }
    }

    var description: String {
        switch self {
        case .copy:
            "Copies new and changed files from the source to the destination, but does not delete files that already exist there."
        case .sync:
            "Makes the destination match the source. Files removed from the source can also be deleted from the destination."
        case .bisync:
            "Performs a two-way sync between local and remote. Use after both sides are already in a known good state."
        }
    }

    var warning: String? {
        switch self {
        case .copy:
            nil
        case .sync:
            "Mirror can delete destination files. Run dry first before using it live."
        case .bisync:
            "Two-way sync is stateful and needs extra care if either side changed outside GDriveVault."
        }
    }

    var rcloneCommand: String { rawValue }
}

enum TransferDirection: String, CaseIterable, Identifiable, Codable, Sendable {
    case upload
    case download

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upload: "Upload"
        case .download: "Download"
        }
    }

    var description: String {
        switch self {
        case .upload:
            "Moves files from the local folder to the selected Google Drive path."
        case .download:
            "Moves files from the selected Google Drive path down to the local folder."
        }
    }

    var sourceLabel: String {
        switch self {
        case .upload: "Local source"
        case .download: "Drive source"
        }
    }

    var destinationLabel: String {
        switch self {
        case .upload: "Drive destination"
        case .download: "Local destination"
        }
    }
}

struct SyncJob: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var localPath: String
    var remotePath: String
    var remoteRootName: String?
    var direction: TransferDirection
    var mode: SyncMode
    var selectedRemoteNames: Set<String>
    var transfers: Int
    var checkers: Int
    var dryRun: Bool
    var cleanupLocalPathAfterRun: String?
    var remoteIncludes: [String]

    static let sample = SyncJob(
        name: "Workspace upload",
        localPath: NSHomeDirectory(),
        remotePath: "Backups/Mac",
        remoteRootName: "MrHandPay",
        direction: .upload,
        mode: .copy,
        selectedRemoteNames: [],
        transfers: 12,
        checkers: 16,
        dryRun: true,
        cleanupLocalPathAfterRun: nil
    )

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case localPath
        case remotePath
        case remoteRootName
        case direction
        case mode
        case selectedRemoteNames
        case transfers
        case checkers
        case dryRun
        case cleanupLocalPathAfterRun
        case remoteIncludes
    }

    init(
        id: UUID = UUID(),
        name: String,
        localPath: String,
        remotePath: String,
        remoteRootName: String?,
        direction: TransferDirection = .upload,
        mode: SyncMode,
        selectedRemoteNames: Set<String>,
        transfers: Int,
        checkers: Int,
        dryRun: Bool,
        cleanupLocalPathAfterRun: String?,
        remoteIncludes: [String] = []
    ) {
        self.id = id
        self.name = name
        self.localPath = localPath
        self.remotePath = remotePath
        self.remoteRootName = remoteRootName
        self.direction = direction
        self.mode = mode
        self.selectedRemoteNames = selectedRemoteNames
        self.transfers = transfers
        self.checkers = checkers
        self.dryRun = dryRun
        self.cleanupLocalPathAfterRun = cleanupLocalPathAfterRun
        self.remoteIncludes = remoteIncludes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        localPath = try container.decode(String.self, forKey: .localPath)
        remotePath = try container.decode(String.self, forKey: .remotePath)
        remoteRootName = try container.decodeIfPresent(String.self, forKey: .remoteRootName)
        direction = try container.decodeIfPresent(TransferDirection.self, forKey: .direction) ?? .upload
        mode = try container.decode(SyncMode.self, forKey: .mode)
        selectedRemoteNames = try container.decode(Set<String>.self, forKey: .selectedRemoteNames)
        transfers = try container.decode(Int.self, forKey: .transfers)
        checkers = try container.decode(Int.self, forKey: .checkers)
        dryRun = try container.decode(Bool.self, forKey: .dryRun)
        cleanupLocalPathAfterRun = try container.decodeIfPresent(String.self, forKey: .cleanupLocalPathAfterRun)
        remoteIncludes = try container.decodeIfPresent([String].self, forKey: .remoteIncludes) ?? []
    }
}

struct InterruptedRun: Hashable, Codable, Sendable {
    var job: SyncJob
    var startedAt: Date
    var reason: String
}

struct RunLogSession: Hashable, Sendable {
    var directoryPath: String
    var summaryPath: String
}

enum RunState: Equatable, Sendable {
    case idle
    case running
    case cancelled
    case finished(code: Int32)
    case skipped(message: String)
    case failed(message: String)

    var label: String {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .cancelled: "Cancelled"
        case .finished(let code): code == 0 ? "Complete" : "Exited \(code)"
        case .skipped: "Skipped"
        case .failed: "Failed"
        }
    }
}

struct SyncRun: Identifiable, Equatable, Sendable {
    let id = UUID()
    let remoteName: String
    let startedAt: Date
    var state: RunState
    var log: String
    var logFilePath: String?
    var transferredBytes: Int64
    var maxTransferBytes: Int64?
    var progress: TransferProgress?
}

struct TransferProgress: Equatable, Sendable {
    var transferredBytes: Int64
    var totalBytes: Int64?
    var percent: Int?
    var speedBytesPerSecond: Int64?
    var eta: String?
    var filesDone: Int?
    var filesTotal: Int?
    var filesPercent: Int?
    var activeFiles: [ActiveFileTransfer]

    var fractionComplete: Double {
        if let totalBytes, totalBytes > 0 {
            return min(1, Double(transferredBytes) / Double(totalBytes))
        }
        if let percent {
            return min(1, Double(percent) / 100)
        }
        return 0
    }
}

struct ActiveFileTransfer: Identifiable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var percent: Int?
    var sizeBytes: Int64?
    var speedBytesPerSecond: Int64?
}

enum AppVersion {
    static let current = "1.3.8"
}

struct UpdateNotification: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
    var actionTitle: String?
    var actionURL: URL?
    var installRequest: UpdateInstallRequest? = nil

    static func == (lhs: UpdateNotification, rhs: UpdateNotification) -> Bool {
        lhs.id == rhs.id
    }
}

struct GoogleChatSettings: Codable, Equatable, Sendable {
    var webhookURL: String
    var notifyStarted: Bool
    var notifyCompleted: Bool
    var notifyFailed: Bool
    var notifyCompletedFiles: Bool
    var fileBatchSize: Int

    var isConfigured: Bool {
        URL(string: webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    static let disabled = GoogleChatSettings(
        webhookURL: "",
        notifyStarted: true,
        notifyCompleted: true,
        notifyFailed: true,
        notifyCompletedFiles: false,
        fileBatchSize: 10
    )
}

struct OrganizationBranding: Codable, Equatable, Sendable {
    var organizationName: String
    var managedByName: String
    var logoPath: String

    var isConfigured: Bool {
        !organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !managedByName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !logoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayName: String {
        let organization = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let manager = managedByName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !organization.isEmpty { return organization }
        if !manager.isEmpty { return manager }
        return "Your organization"
    }

    var managedStatement: String {
        let organization = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let manager = managedByName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !organization.isEmpty, !manager.isEmpty {
            return "Licensed to \(organization) and managed by \(manager), on behalf of GDriveVault."
        }
        if !organization.isEmpty {
            return "Licensed to \(organization), on behalf of GDriveVault."
        }
        if !manager.isEmpty {
            return "Managed by \(manager), on behalf of GDriveVault."
        }
        return "Managed on behalf of GDriveVault."
    }

    static let empty = OrganizationBranding(
        organizationName: "",
        managedByName: "",
        logoPath: ""
    )
}

struct RemoteControlSettings: Codable, Equatable, Sendable {
    static let productionServerURL = "https://app.gdrivevault.com"

    var serverURL: String
    var deviceName: String
    var licenseKey: String
    var approvalRequestID: String?
    var deviceID: String?
    var token: String?
    var isEnabled: Bool
    var pollIntervalSeconds: Int

    enum CodingKeys: String, CodingKey {
        case serverURL
        case deviceName
        case licenseKey
        case approvalRequestID
        case deviceID
        case token
        case isEnabled
        case pollIntervalSeconds
    }

    init(
        serverURL: String,
        deviceName: String,
        licenseKey: String,
        approvalRequestID: String?,
        deviceID: String?,
        token: String?,
        isEnabled: Bool,
        pollIntervalSeconds: Int
    ) {
        self.serverURL = serverURL
        self.deviceName = deviceName
        self.licenseKey = licenseKey
        self.approvalRequestID = approvalRequestID
        self.deviceID = deviceID
        self.token = token
        self.isEnabled = isEnabled
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? Self.productionServerURL
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? (Host.current().localizedName ?? "GDriveVault Mac")
        licenseKey = try container.decodeIfPresent(String.self, forKey: .licenseKey) ?? ""
        approvalRequestID = try container.decodeIfPresent(String.self, forKey: .approvalRequestID)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID)
        token = try container.decodeIfPresent(String.self, forKey: .token)
        isEnabled = true
        pollIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? 5
    }

    var isRegistered: Bool {
        deviceID != nil && token != nil && hasLicenseKey
    }

    var hasLicenseKey: Bool {
        !licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isPendingApproval: Bool {
        approvalRequestID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && !isRegistered
    }

    var normalizedServerURL: String {
        Self.productionServerURL
    }

    var lockedToProductionServer: RemoteControlSettings {
        var updated = self
        let previousURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        if previousURL != Self.productionServerURL {
            updated.deviceID = nil
            updated.token = nil
            updated.approvalRequestID = nil
        }
        updated.serverURL = Self.productionServerURL
        updated.licenseKey = updated.licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.isEnabled = true
        return updated
    }

    static let disabled = RemoteControlSettings(
        serverURL: productionServerURL,
        deviceName: Host.current().localizedName ?? "GDriveVault Mac",
        licenseKey: "",
        approvalRequestID: nil,
        deviceID: nil,
        token: nil,
        isEnabled: true,
        pollIntervalSeconds: 5
    )
}

struct RemoteControlCommand: Decodable, Sendable {
    var id: String
    var command: String
    var payload: [String: String]?
}

struct RemoteControlHeartbeat: Encodable, Sendable {
    var status: String
    var jobName: String?
    var remoteName: String?
    var transferredBytes: Int64
    var speedBps: Int64?
    var eta: String?
    var accountUsage: [String: Int64]
    var appVersion: String
    var hostname: String?
    var platform: String
    var osVersion: String
    var arch: String
    var syncRoot: String?
    var currentFile: String?
    var filesCompleted: Int?
    var filesTotal: Int?
    var filesAdded: Int
    var filesUpdated: Int
    var filesDeleted: Int
    var bytesAdded: Int64
    var bytesUpdated: Int64
    var recentChanges: [RemoteControlChange]
    var internetDownloadMbps: Double?
    var internetUploadMbps: Double?
    var internetPublicIP: String?
    var internetLocation: String?
    var internetProvider: String?
    var speedTestedAt: Date?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case status
        case jobName = "job_name"
        case remoteName = "remote_name"
        case transferredBytes = "transferred_bytes"
        case speedBps = "speed_bps"
        case eta
        case accountUsage = "account_usage"
        case appVersion = "app_version"
        case hostname
        case platform
        case osVersion = "os_version"
        case arch
        case syncRoot = "sync_root"
        case currentFile = "current_file"
        case filesCompleted = "files_completed"
        case filesTotal = "files_total"
        case filesAdded = "files_added"
        case filesUpdated = "files_updated"
        case filesDeleted = "files_deleted"
        case bytesAdded = "bytes_added"
        case bytesUpdated = "bytes_updated"
        case recentChanges = "recent_changes"
        case internetDownloadMbps = "internet_download_mbps"
        case internetUploadMbps = "internet_upload_mbps"
        case internetPublicIP = "internet_public_ip"
        case internetLocation = "internet_location"
        case internetProvider = "internet_provider"
        case speedTestedAt = "speed_tested_at"
        case error
    }
}

struct RemoteControlChange: Encodable, Hashable, Sendable {
    var action: String
    var path: String
    var bytes: Int64?
    var remoteName: String
    var timestamp: Date

    enum CodingKeys: String, CodingKey {
        case action
        case path
        case bytes
        case remoteName = "remote_name"
        case timestamp
    }
}

struct BandwidthTestResult: Codable, Equatable, Sendable {
    var testedAt: Date
    var downloadMbps: Double
    var uploadMbps: Double?
    var bytesDownloaded: Int64
    var bytesUploaded: Int64?
    var durationSeconds: Double
    var uploadDurationSeconds: Double?
    var endpoint: String
    var publicIP: String?
    var location: String?
    var provider: String?

    var displaySpeed: String {
        "\(String(format: "%.1f", downloadMbps)) Mbps"
    }

    var displayUploadSpeed: String {
        guard let uploadMbps else { return "Unavailable" }
        return "\(String(format: "%.1f", uploadMbps)) Mbps"
    }

    var displayTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        return formatter.string(from: testedAt)
    }
}
