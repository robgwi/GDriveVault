import Foundation

actor BandwidthTestStore {
    private let defaults = UserDefaults.standard
    private let key = "gdrivevault.bandwidthTest.latest.v1"
    private let legacyKey = "skyvault.bandwidthTest.latest.v1"

    func load() -> BandwidthTestResult? {
        let data = PreferenceMigration.data(forKey: key, legacyKeys: [legacyKey], defaults: defaults)
        guard let data,
              let decoded = try? JSONDecoder().decode(BandwidthTestResult.self, from: data) else { return nil }
        return decoded
    }

    func save(_ result: BandwidthTestResult) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }
}
