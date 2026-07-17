import Foundation

actor BandwidthTestService {
    enum TestError: LocalizedError {
        case invalidEndpoint
        case emptyResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                "The bandwidth test endpoint is not valid."
            case .emptyResponse:
                "The bandwidth test did not receive any data."
            case .httpStatus(let status):
                "The bandwidth test returned HTTP \(status)."
            }
        }
    }

    private let defaultBytes = 25_000_000
    private let uploadBytes = 5_000_000
    private let baseEndpoint = "https://speed.cloudflare.com/__down"
    private let uploadEndpoint = "https://speed.cloudflare.com/__up"
    private let metaEndpoint = "https://speed.cloudflare.com/meta"

    func run() async throws -> BandwidthTestResult {
        var components = URLComponents(string: baseEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "bytes", value: "\(defaultBytes)"),
            URLQueryItem(name: "cachebust", value: UUID().uuidString)
        ]

        guard let url = components?.url else { throw TestError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30

        let startedAt = Date()
        let start = ContinuousClock.now
        let (data, response) = try await URLSession.shared.data(for: request)
        let duration = start.duration(to: ContinuousClock.now)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw TestError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard !data.isEmpty else { throw TestError.emptyResponse }

        let seconds = max(0.001, Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000)
        let bytes = Int64(data.count)
        let mbps = Double(bytes) * 8 / seconds / 1_000_000
        let upload = await uploadSample()
        let meta = await metadata()

        return BandwidthTestResult(
            testedAt: startedAt,
            downloadMbps: mbps,
            uploadMbps: upload?.mbps,
            bytesDownloaded: bytes,
            bytesUploaded: upload?.bytes,
            durationSeconds: seconds,
            uploadDurationSeconds: upload?.seconds,
            endpoint: baseEndpoint,
            publicIP: meta?.clientIP,
            location: meta?.locationText,
            provider: meta?.providerText
        )
    }

    private func uploadSample() async -> (mbps: Double, bytes: Int64, seconds: Double)? {
        guard let url = URL(string: uploadEndpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30
        request.httpBody = Data(repeating: 0x2a, count: uploadBytes)

        do {
            let start = ContinuousClock.now
            let (_, response) = try await URLSession.shared.data(for: request)
            let duration = start.duration(to: ContinuousClock.now)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            let seconds = max(0.001, Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000)
            let bytes = Int64(uploadBytes)
            return (Double(bytes) * 8 / seconds / 1_000_000, bytes, seconds)
        } catch {
            return nil
        }
    }

    private func metadata() async -> SpeedMetadata? {
        guard let url = URL(string: metaEndpoint) else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(SpeedMetadata.self, from: data)
        } catch {
            return nil
        }
    }
}

private struct SpeedMetadata: Decodable {
    var clientIP: String?
    var city: String?
    var region: String?
    var country: String?
    var asOrganization: String?
    var colo: String?

    enum CodingKeys: String, CodingKey {
        case clientIP = "clientIp"
        case city
        case region
        case country
        case asOrganization
        case colo
    }

    var locationText: String? {
        let parts = [city, region, country]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        if !parts.isEmpty { return parts.joined(separator: ", ") }
        return colo
    }

    var providerText: String? {
        asOrganization?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
