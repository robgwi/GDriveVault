import Foundation

actor RunRecoveryStore {
    private let defaults = UserDefaults.standard
    private let key = "skyvault.interruptedRun.v1"

    func load() -> InterruptedRun? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(InterruptedRun.self, from: data)
    }

    func save(_ interruptedRun: InterruptedRun) {
        guard let data = try? JSONEncoder().encode(interruptedRun) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
