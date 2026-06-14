import Foundation

actor RemoteControlService {
    enum RemoteControlError: LocalizedError {
        case invalidServerURL
        case missingToken
        case httpStatus(Int, String?)

        var errorDescription: String? {
            switch self {
            case .invalidServerURL:
                "The remote control server URL is not valid."
            case .missingToken:
                "Register this Mac before connecting to remote control."
            case .httpStatus(let status, let message):
                if let message, !message.isEmpty {
                    "Remote control server returned HTTP \(status): \(message)"
                } else {
                    "Remote control server returned HTTP \(status)."
                }
            }
        }
    }

    func register(settings: RemoteControlSettings) async throws -> RemoteControlSettings {
        let url = try endpoint("/api/devices/register", settings: settings)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RegisterRequest(
            name: settings.deviceName,
            licenseKey: settings.hasLicenseKey ? settings.licenseKey : nil,
            approvalRequestID: settings.approvalRequestID
        ))

        let response: RegisterResponse = try await send(request)
        var updated = settings
        if response.isPendingApprovalResponse {
            updated.deviceID = nil
            updated.token = nil
            updated.approvalRequestID = response.approvalRequestID ?? settings.approvalRequestID
        } else {
            updated.deviceID = response.id
            updated.token = response.token
            updated.deviceName = response.name ?? settings.deviceName
            updated.licenseKey = response.licenseKey ?? settings.licenseKey
            updated.approvalRequestID = nil
        }
        return updated
    }

    func sendHeartbeat(_ heartbeat: RemoteControlHeartbeat, settings: RemoteControlSettings) async throws {
        var request = try authorizedRequest("/api/agent/heartbeat", settings: settings)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(heartbeat)
        let _: EmptyResponse = try await send(request)
    }

    func fetchCommands(settings: RemoteControlSettings) async throws -> [RemoteControlCommand] {
        var request = try authorizedRequest("/api/agent/commands", settings: settings)
        request.httpMethod = "GET"
        return try await send(request)
    }

    func acknowledge(commandID: String, settings: RemoteControlSettings) async throws {
        var request = try authorizedRequest("/api/agent/commands/\(commandID)/ack", settings: settings)
        request.httpMethod = "POST"
        let _: EmptyResponse = try await send(request)
    }

    func uploadSettingsBackup(_ backup: GDriveVaultBackup, settings: RemoteControlSettings) async throws -> String {
        var request = try authorizedRequest("/api/agent/settings-backup", settings: settings)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(backup)

        let response: SettingsBackupResponse = try await send(request)
        return response.backupID
    }

    func downloadSettingsBackup(backupID: String, settings: RemoteControlSettings) async throws -> GDriveVaultBackup {
        var request = try authorizedRequest("/api/agent/settings-backups/\(backupID)", settings: settings)
        request.httpMethod = "GET"
        let response: SettingsBackupDownloadResponse = try await send(request)
        return response.backup
    }

    private func authorizedRequest(_ path: String, settings: RemoteControlSettings) throws -> URLRequest {
        guard let token = settings.token else { throw RemoteControlError.missingToken }
        let url = try endpoint(path, settings: settings)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func endpoint(_ path: String, settings: RemoteControlSettings) throws -> URL {
        let base = settings.normalizedServerURL
        guard let url = URL(string: base + path) else {
            throw RemoteControlError.invalidServerURL
        }
        return url
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteControlError.httpStatus(-1, nil)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw RemoteControlError.httpStatus(httpResponse.statusCode, message)
        }

        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

private struct RegisterRequest: Encodable {
    var name: String
    var licenseKey: String?
    var approvalRequestID: String?

    enum CodingKeys: String, CodingKey {
        case name
        case licenseKey = "license_key"
        case approvalRequestID = "approval_request_id"
    }
}

private struct RegisterResponse: Decodable {
    var id: String?
    var name: String?
    var token: String?
    var status: String?
    var approvalRequestID: String?
    var licenseKey: String?

    var isPendingApprovalResponse: Bool {
        guard id == nil || token == nil else { return false }
        return approvalRequestID != nil || status == "pending" || status == "pending_approval" || status == "approved"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case token
        case status
        case approvalRequestID = "approval_request_id"
        case licenseKey = "license_key"
    }
}

private struct EmptyResponse: Decodable {}

private struct SettingsBackupResponse: Decodable {
    var backupID: String

    enum CodingKeys: String, CodingKey {
        case backupID = "backup_id"
    }
}

private struct SettingsBackupDownloadResponse: Decodable {
    var backup: GDriveVaultBackup
}
