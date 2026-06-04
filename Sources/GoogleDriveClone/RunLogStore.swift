import Foundation

actor RunLogStore {
    private let fileManager = FileManager.default

    func createSession(for job: SyncJob) throws -> RunLogSession {
        let root = try logsRootURL()
        let stamp = Self.timestampFormatter.string(from: Date())
        let folderName = "\(stamp)-\(Self.safeFileName(job.name))"
        let directory = root.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        return RunLogSession(
            directoryPath: directory.path,
            summaryPath: directory.appendingPathComponent("summary.txt").path
        )
    }

    nonisolated func logFileURL(for remoteName: String, in session: RunLogSession) -> URL {
        URL(fileURLWithPath: session.directoryPath)
            .appendingPathComponent("\(Self.safeFileName(remoteName.trimmingCharacters(in: CharacterSet(charactersIn: ":")))).log")
    }

    func writeSummary(session: RunLogSession, job: SyncJob, runs: [SyncRun], finalStatus: String) throws {
        let lines = [
            "SkyVault for Google Sync Summary",
            "Started: \(Self.displayFormatter.string(from: runs.map(\.startedAt).min() ?? Date()))",
            "Finished: \(Self.displayFormatter.string(from: Date()))",
            "Status: \(finalStatus)",
            "",
            "Job: \(job.name)",
            "Mode: \(job.mode.label)",
            "Dry run: \(job.dryRun ? "Yes" : "No")",
            "Local folder: \(job.localPath)",
            "Remote path: \(job.remotePath)",
            "Selected profiles: \(job.selectedRemoteNames.sorted().joined(separator: ", "))",
            "",
            "Profile Runs:",
            runs.map(Self.summaryLine(for:)).joined(separator: "\n")
        ]
        .joined(separator: "\n")
        .appending("\n")

        try lines.write(to: URL(fileURLWithPath: session.summaryPath), atomically: true, encoding: .utf8)
    }

    private func logsRootURL() throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support
            .appendingPathComponent("SkyVault for Google", isDirectory: true)
            .appendingPathComponent("Run Logs", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func summaryLine(for run: SyncRun) -> String {
        let logPath = run.logFilePath ?? "No log file"
        return "- \(run.remoteName): \(run.state.label), transferred \(TransferStatsParser.formatBytes(run.transferredBytes)), log \(logPath)"
    }

    private static func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return name.isEmpty ? "sync" : name
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
