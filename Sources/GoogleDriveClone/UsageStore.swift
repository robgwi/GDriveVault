import Foundation

actor UsageStore {
    private let defaults = UserDefaults.standard
    private let key = "skyvault.accountUsage.v2"
    private let legacyKey = "skyvault.accountUsage.v1"
    private let quotaWindow: TimeInterval = 24 * 60 * 60

    func load() -> [AccountUsage] {
        let events = loadEvents()
        let grouped = Dictionary(grouping: events, by: \.remoteName)
        return grouped
            .map { remoteName, events in
                AccountUsage(
                    remoteName: remoteName,
                    dateKey: Self.todayKey(),
                    bytesTransferred: events.reduce(Int64(0)) { $0 + $1.bytes }
                )
            }
            .sorted { $0.remoteName.localizedCaseInsensitiveCompare($1.remoteName) == .orderedAscending }
    }

    func usage(for remoteName: String) -> AccountUsage {
        load().first(where: { $0.remoteName == remoteName }) ?? AccountUsage(
            remoteName: remoteName,
            dateKey: Self.todayKey(),
            bytesTransferred: 0
        )
    }

    func setTransferredBytes(_ bytes: Int64, for remoteName: String) {
        var events = loadEvents().filter { $0.remoteName != remoteName }
        events.append(UsageEvent(remoteName: remoteName, date: Date(), bytes: max(0, bytes)))
        saveEvents(events)
    }

    func addTransferredBytes(_ bytes: Int64, for remoteName: String) {
        guard bytes > 0 else { return }
        var events = loadEvents()
        events.append(UsageEvent(remoteName: remoteName, date: Date(), bytes: bytes))
        saveEvents(events)
    }

    func reset(remoteName: String) {
        saveEvents(loadEvents().filter { $0.remoteName != remoteName })
    }

    func resetAll() {
        saveEvents([])
    }

    func save(_ usages: [AccountUsage]) {
        let events = usages
            .filter { $0.bytesTransferred > 0 }
            .map { UsageEvent(remoteName: $0.remoteName, date: Date(), bytes: $0.bytesTransferred) }
        saveEvents(events)
    }

    private func loadEvents() -> [UsageEvent] {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UsageEvent].self, from: data) {
            return prune(decoded)
        }

        return migrateLegacyUsage()
    }

    private func saveEvents(_ events: [UsageEvent]) {
        guard let data = try? JSONEncoder().encode(prune(events)) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }

    private func prune(_ events: [UsageEvent]) -> [UsageEvent] {
        let cutoff = Date().addingTimeInterval(-quotaWindow)
        return events.filter { $0.date >= cutoff && $0.bytes > 0 }
    }

    private func migrateLegacyUsage() -> [UsageEvent] {
        guard let data = defaults.data(forKey: legacyKey),
              let decoded = try? JSONDecoder().decode([AccountUsage].self, from: data)
        else {
            return []
        }

        let today = Self.todayKey()
        let events = decoded
            .filter { $0.dateKey == today && $0.bytesTransferred > 0 }
            .map { UsageEvent(remoteName: $0.remoteName, date: Date(), bytes: $0.bytesTransferred) }
        saveEvents(events)
        return events
    }

    static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private struct UsageEvent: Codable, Sendable {
    var remoteName: String
    var date: Date
    var bytes: Int64
}
