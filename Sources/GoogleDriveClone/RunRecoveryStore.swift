import Foundation

actor RunRecoveryStore {
    private let defaults = UserDefaults.standard
    private let key = "gdrivevault.interruptedRun.v1"
    private let legacyKey = "skyvault.interruptedRun.v1"

    func load() -> InterruptedRun? {
        let data = PreferenceMigration.data(forKey: key, legacyKeys: [legacyKey], defaults: defaults)
        guard let data,
              let decoded = try? JSONDecoder().decode(InterruptedRun.self, from: data) else { return nil }
        return decoded
    }

    func save(_ interruptedRun: InterruptedRun) {
        guard let data = try? JSONEncoder().encode(interruptedRun) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
