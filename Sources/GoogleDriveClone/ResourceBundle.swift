import Foundation

extension Bundle {
    static var gdriveVaultResources: Bundle {
        let bundleName = "GDriveVault_GoogleDriveClone.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName)
        ].compactMap { $0 }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        return .main
    }
}
