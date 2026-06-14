import Foundation

enum PreferenceMigration {
    private static let legacyDomains = [
        "SkyVaultForGoogle",
        "GoogleDriveClone"
    ]

    static func data(forKey key: String, legacyKeys: [String], defaults: UserDefaults = .standard) -> Data? {
        if let data = defaults.data(forKey: key) {
            return data
        }

        for domain in legacyDomains {
            guard let legacyDefaults = UserDefaults(suiteName: domain) else { continue }
            for legacyKey in legacyKeys {
                if let data = legacyDefaults.data(forKey: legacyKey) {
                    defaults.set(data, forKey: key)
                    defaults.synchronize()
                    return data
                }
            }
        }

        for legacyKey in legacyKeys {
            if let data = defaults.data(forKey: legacyKey) {
                defaults.set(data, forKey: key)
                defaults.synchronize()
                return data
            }
        }

        return nil
    }
}
