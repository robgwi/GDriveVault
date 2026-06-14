import Foundation

actor GoogleChatService {
    enum ChatError: LocalizedError {
        case missingWebhook
        case invalidWebhookURL
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .missingWebhook:
                "Add a Google Chat Space webhook URL first."
            case .invalidWebhookURL:
                "The Google Chat webhook URL is not valid."
            case .httpStatus(let status):
                "Google Chat returned HTTP \(status)."
            }
        }
    }

    func send(_ message: String, settings: GoogleChatSettings) async throws {
        let rawURL = settings.webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty else { throw ChatError.missingWebhook }
        guard let url = URL(string: rawURL) else { throw ChatError.invalidWebhookURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatMessage(text: message))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw ChatError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}

private struct ChatMessage: Encodable {
    var text: String
}
