import CryptoKit
import Foundation

struct UpdateInstallRequest: Sendable {
    var version: String
    var downloadURL: URL
    var sha256: String?

    init(version: String, downloadURL: URL, sha256: String? = nil) {
        self.version = version
        self.downloadURL = downloadURL
        self.sha256 = sha256?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

actor UpdateInstaller {
    enum InstallError: LocalizedError {
        case notPackagedApp
        case invalidDownload
        case checksumMismatch(expected: String, actual: String)
        case missingExtractedApp
        case helperLaunchFailed

        var errorDescription: String? {
            switch self {
            case .notPackagedApp:
                "Self-update only works from the packaged GDriveVault.app build."
            case .invalidDownload:
                "The update download did not return a valid zip file."
            case .checksumMismatch(let expected, let actual):
                "The update checksum did not match. Expected \(expected), got \(actual)."
            case .missingExtractedApp:
                "The downloaded update did not contain GDriveVault.app."
            case .helperLaunchFailed:
                "Could not launch the update installer helper."
            }
        }
    }

    func prepareInstall(_ request: UpdateInstallRequest) async throws -> URL {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            throw InstallError.notPackagedApp
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GDriveVault Updates", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let extractURL = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractURL, withIntermediateDirectories: true)

        let zipURL = root.appendingPathComponent("GDriveVault-\(request.version).zip")
        let (downloadedURL, response) = try await URLSession.shared.download(from: request.downloadURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw InstallError.invalidDownload
        }

        try FileManager.default.moveItem(at: downloadedURL, to: zipURL)
        if let expected = request.sha256, !expected.isEmpty {
            let actual = try sha256(for: zipURL)
            guard actual == expected else {
                throw InstallError.checksumMismatch(expected: expected, actual: actual)
            }
        }

        try run("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, extractURL.path])
        let newAppURL = extractURL.appendingPathComponent("GDriveVault.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: newAppURL.path) else {
            throw InstallError.missingExtractedApp
        }

        let helperURL = root.appendingPathComponent("install-update.sh")
        try installerScript(appURL: appURL, newAppURL: newAppURL).write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        return helperURL
    }

    func launchInstaller(helperURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [helperURL.path]
        do {
            try process.run()
        } catch {
            throw InstallError.helperLaunchFailed
        }
    }

    private func sha256(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw InstallError.invalidDownload
        }
    }

    private func installerScript(appURL: URL, newAppURL: URL) -> String {
        let pid = ProcessInfo.processInfo.processIdentifier
        return """
        #!/bin/bash
        set -euo pipefail

        APP_PATH=\(shellQuote(appURL.path))
        NEW_APP=\(shellQuote(newAppURL.path))
        PID=\(pid)
        BACKUP_PATH="${APP_PATH}.previous-$(date +%Y%m%d%H%M%S)"

        for _ in {1..60}; do
          if ! kill -0 "$PID" 2>/dev/null; then
            break
          fi
          sleep 1
        done

        if kill -0 "$PID" 2>/dev/null; then
          exit 1
        fi

        mv "$APP_PATH" "$BACKUP_PATH"
        if ! /usr/bin/ditto "$NEW_APP" "$APP_PATH"; then
          rm -rf "$APP_PATH"
          mv "$BACKUP_PATH" "$APP_PATH"
          exit 1
        fi

        /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
        /usr/bin/open -n "$APP_PATH"
        exit 0
        """
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
