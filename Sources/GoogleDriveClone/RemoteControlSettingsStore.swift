import Foundation

actor RemoteControlSettingsStore {
    private let defaults = UserDefaults.standard
    private let key = "gdrivevault.remoteControlSettings.v1"
    private let legacyKey = "skyvault.remoteControlSettings.v1"

    func load() -> RemoteControlSettings {
        let data = PreferenceMigration.data(forKey: key, legacyKeys: [legacyKey], defaults: defaults)
        guard let data,
              let decoded = try? JSONDecoder().decode(RemoteControlSettings.self, from: data)
        else {
            return .disabled
        }

        let locked = decoded.lockedToProductionServer
        if locked != decoded {
            save(locked)
        }
        return locked
    }

    func save(_ settings: RemoteControlSettings) {
        guard let data = try? JSONEncoder().encode(settings.lockedToProductionServer) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }
}
