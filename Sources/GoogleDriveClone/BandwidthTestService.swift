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
    private let baseEndpoint = "https://speed.cloudflare.com/__down"

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

        return BandwidthTestResult(
            testedAt: startedAt,
            downloadMbps: mbps,
            bytesDownloaded: bytes,
            durationSeconds: seconds,
            endpoint: baseEndpoint
        )
    }
}
