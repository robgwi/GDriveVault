import Foundation

struct GDriveVaultBackup: Codable, Sendable {
    var schemaVersion: Int
    var createdAt: Date
    var rcloneConfigPath: String
    var rcloneConfigContents: String
    var syncJobs: [SyncJob]
    var accountUsages: [AccountUsage]
    var googleChatSettings: GoogleChatSettings?
    var remoteControlSettings: RemoteControlSettings?
}

actor BackupStore {
    enum BackupError: LocalizedError {
        case invalidBackup

        var errorDescription: String? {
            switch self {
            case .invalidBackup: "The selected file is not a valid GDriveVault backup."
            }
        }
    }

    func write(_ backup: GDriveVaultBackup, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        try data.write(to: url, options: [.atomic])
    }

    func read(from url: URL) throws -> GDriveVaultBackup {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(GDriveVaultBackup.self, from: data)
        } catch {
            throw BackupError.invalidBackup
        }
    }
}
