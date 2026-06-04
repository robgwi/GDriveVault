import Foundation

actor UsageStore {
    private let defaults = UserDefaults.standard
    private let key = "skyvault.accountUsage.v1"

    func load() -> [AccountUsage] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AccountUsage].self, from: data)
        else {
            return []
        }

        let today = Self.todayKey()
        return decoded
            .filter { $0.dateKey == today }
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
        var usages = load()
        let today = Self.todayKey()

        if let index = usages.firstIndex(where: { $0.remoteName == remoteName }) {
            usages[index].dateKey = today
            usages[index].bytesTransferred = max(usages[index].bytesTransferred, bytes)
        } else {
            usages.append(AccountUsage(remoteName: remoteName, dateKey: today, bytesTransferred: max(0, bytes)))
        }

        save(usages)
    }

    func addTransferredBytes(_ bytes: Int64, for remoteName: String) {
        guard bytes > 0 else { return }
        var usages = load()
        let today = Self.todayKey()

        if let index = usages.firstIndex(where: { $0.remoteName == remoteName }) {
            usages[index].dateKey = today
            usages[index].bytesTransferred += bytes
        } else {
            usages.append(AccountUsage(remoteName: remoteName, dateKey: today, bytesTransferred: bytes))
        }

        save(usages)
    }

    func reset(remoteName: String) {
        var usages = load()
        usages.removeAll { $0.remoteName == remoteName }
        save(usages)
    }

    func resetAll() {
        save([])
    }

    func save(_ usages: [AccountUsage]) {
        guard let data = try? JSONEncoder().encode(usages) else { return }
        defaults.set(data, forKey: key)
    }

    static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
