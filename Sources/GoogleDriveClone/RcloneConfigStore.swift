import Foundation

actor RcloneConfigStore {
    enum ConfigError: LocalizedError {
        case unreadableConfig(String)
        case invalidProfileName(String)
        case duplicateProfileName(String)
        case invalidKey(String)

        var errorDescription: String? {
            switch self {
            case .unreadableConfig(let message): message
            case .invalidProfileName(let name): "Profile name '\(name)' is not valid."
            case .duplicateProfileName(let name): "Profile name '\(name)' is used more than once."
            case .invalidKey(let key): "Setting key '\(key)' is not valid."
            }
        }
    }

    func load(using rclone: RcloneService) async throws -> RcloneConfigDocument {
        let path = try await rclone.configFilePath()
        let url = URL(fileURLWithPath: path)
        let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return RcloneConfigDocument(path: path, profiles: parse(contents))
    }

    func rawConfig(using rclone: RcloneService) async throws -> (path: String, contents: String) {
        let path = try await rclone.configFilePath()
        let contents = (try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)) ?? ""
        return (path, contents)
    }

    func restoreRawConfig(_ contents: String, to path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: path) {
            let backupURL = url.deletingPathExtension().appendingPathExtension("conf.\(backupStamp()).pre-restore.bak")
            try FileManager.default.copyItem(at: url, to: backupURL)
        }

        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func loadProfiles(from url: URL) async throws -> [RcloneProfileDraft] {
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            return try validatedProfiles(parse(contents))
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.unreadableConfig("Could not import '\(url.lastPathComponent)'. Make sure it is a readable rclone config file.")
        }
    }

    func save(_ document: RcloneConfigDocument) async throws {
        let profiles = try validatedProfiles(document.profiles)
        let url = URL(fileURLWithPath: document.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: document.path) {
            let backupURL = url.deletingPathExtension().appendingPathExtension("conf.\(backupStamp()).bak")
            try FileManager.default.copyItem(at: url, to: backupURL)
        }

        let rendered = render(profiles)
        try rendered.write(to: url, atomically: true, encoding: .utf8)
    }

    private func parse(_ contents: String) -> [RcloneProfileDraft] {
        var profiles: [RcloneProfileDraft] = []
        var currentName: String?
        var currentEntries: [RcloneConfigEntry] = []

        func flush() {
            guard let currentName else { return }
            profiles.append(RcloneProfileDraft(name: currentName, entries: currentEntries))
            currentEntries = []
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                flush()
                currentName = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }

            guard currentName != nil, let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            currentEntries.append(RcloneConfigEntry(key: String(key), value: String(value)))
        }

        flush()
        return profiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func render(_ profiles: [RcloneProfileDraft]) -> String {
        profiles.map { profile in
            var lines = ["[\(profile.name)]"]
            lines.append(contentsOf: profile.entries.map { "\($0.key) = \($0.value)" })
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
        .appending("\n")
    }

    private func validatedProfiles(_ profiles: [RcloneProfileDraft]) throws -> [RcloneProfileDraft] {
        var seenNames = Set<String>()
        var validated: [RcloneProfileDraft] = []

        for profile in profiles {
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidSectionName(name) else { throw ConfigError.invalidProfileName(profile.name) }
            guard seenNames.insert(name.lowercased()).inserted else { throw ConfigError.duplicateProfileName(name) }

            let entries = try profile.entries.compactMap { entry -> RcloneConfigEntry? in
                let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty || !value.isEmpty else { return nil }
                guard isValidKey(key) else { throw ConfigError.invalidKey(entry.key) }
                return RcloneConfigEntry(id: entry.id, key: key, value: value)
            }

            validated.append(RcloneProfileDraft(id: profile.id, name: name, entries: entries))
        }

        return validated.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func isValidSectionName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("[") && !name.contains("]") && !name.contains("\n")
    }

    private func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && !key.contains("=") && !key.contains("\n")
    }

    private func backupStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
