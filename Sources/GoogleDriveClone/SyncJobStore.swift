import Foundation

actor SyncJobStore {
    private let defaults = UserDefaults.standard
    private let key = "skyvault.syncJobs.v1"

    func load() -> [SyncJob] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SyncJob].self, from: data)
        else {
            return []
        }

        return decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func save(_ jobs: [SyncJob]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        defaults.set(data, forKey: key)
    }
}
