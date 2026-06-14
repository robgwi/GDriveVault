import Foundation

actor UpdateChecker {
    func check(currentVersion: String, settings: RemoteControlSettings) async throws -> UpdateCheckResult {
        let url = try updateFeedURL(settings: settings)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("GDriveVault/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateError.httpStatus(httpResponse.statusCode)
        }

        let update = try JSONDecoder().decode(ControlUpdate.self, from: data)
        let latestVersion = Self.normalizedVersion(update.latest)
        let hasUpdate = Self.compareVersions(latestVersion, currentVersion) == .orderedDescending

        return UpdateCheckResult(
            hasUpdate: hasUpdate,
            latestVersion: latestVersion,
            currentVersion: currentVersion,
            releaseURL: update.downloadURL,
            releaseName: update.notes
        )
    }

    private func updateFeedURL(settings: RemoteControlSettings) throws -> URL {
        guard !settings.normalizedServerURL.isEmpty,
              let url = URL(string: settings.normalizedServerURL + "/api/updates/latest")
        else {
            throw UpdateError.invalidServerURL
        }
        return url
    }

    private static func normalizedVersion(_ version: String) -> String {
        let trimmed = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0
            if leftPart > rightPart { return .orderedDescending }
            if leftPart < rightPart { return .orderedAscending }
        }

        return .orderedSame
    }
}

struct UpdateCheckResult: Sendable {
    var hasUpdate: Bool
    var latestVersion: String
    var currentVersion: String
    var releaseURL: URL
    var releaseName: String?
}

private struct ControlUpdate: Decodable {
    var latest: String
    var downloadURL: URL
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case latest
        case downloadURL = "download_url"
        case notes
    }
}

enum UpdateError: LocalizedError {
    case invalidResponse
    case invalidServerURL
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The update server returned an invalid response."
        case .invalidServerURL:
            "Set a valid GDriveVault Control server URL before checking for updates."
        case .httpStatus(let status):
            "The update server returned HTTP \(status)."
        }
    }
}
