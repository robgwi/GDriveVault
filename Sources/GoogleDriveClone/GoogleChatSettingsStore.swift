import Foundation

actor GoogleChatSettingsStore {
    private let defaults = UserDefaults.standard
    private let key = "gdrivevault.googleChatSettings.v1"
    private let legacyKey = "skyvault.googleChatSettings.v1"

    func load() -> GoogleChatSettings {
        let data = PreferenceMigration.data(forKey: key, legacyKeys: [legacyKey], defaults: defaults)
        guard let data,
              let decoded = try? JSONDecoder().decode(GoogleChatSettings.self, from: data)
        else {
            return .disabled
        }

        return decoded
    }

    func save(_ settings: GoogleChatSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }
}
