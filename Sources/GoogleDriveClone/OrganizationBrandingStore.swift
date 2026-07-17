import Foundation

actor OrganizationBrandingStore {
    private let defaults = UserDefaults.standard
    private let key = "gdrivevault.organizationBranding.v1"

    func load() -> OrganizationBranding {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(OrganizationBranding.self, from: data) else {
            return .empty
        }
        return decoded
    }

    func save(_ branding: OrganizationBranding) {
        if let data = try? JSONEncoder().encode(branding) {
            defaults.set(data, forKey: key)
        }
    }
}
