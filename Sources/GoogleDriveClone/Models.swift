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
            "Uploads new and changed files to the remote path, but does not delete files that already exist there."
        case .sync:
            "Makes the remote path match the local folder. Files removed locally can also be deleted remotely."
        case .bisync:
            "Performs a two-way sync between local and remote. Use after both sides are already in a known good state."
        }
    }

    var warning: String? {
        switch self {
        case .copy:
            nil
        case .sync:
            "Mirror can delete remote files. Run dry first before using it live."
        case .bisync:
            "Two-way sync is stateful and needs extra care if either side changed outside SkyVault."
        }
    }

    var rcloneCommand: String { rawValue }
}

struct SyncJob: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name: String
    var localPath: String
    var remotePath: String
    var mode: SyncMode
    var selectedRemoteNames: Set<String>
    var transfers: Int
    var checkers: Int
    var dryRun: Bool

    static let sample = SyncJob(
        name: "Workspace upload",
        localPath: NSHomeDirectory(),
        remotePath: "Backups/Mac",
        mode: .copy,
        selectedRemoteNames: [],
        transfers: 12,
        checkers: 16,
        dryRun: true
    )
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
