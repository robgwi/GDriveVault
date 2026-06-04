import Foundation

final class RcloneProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process?) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

actor RcloneService {
    enum ServiceError: LocalizedError {
        case launchFailed(String)
        case missingRemote

        var errorDescription: String? {
            switch self {
            case .launchFailed(let message): message
            case .missingRemote: "Choose at least one rclone remote."
            }
        }
    }

    func listRemotes() async throws -> [RcloneRemote] {
        let output = try await runCapture(arguments: ["listremotes"])
        return output
            .split(separator: "\n")
            .map { RcloneRemote(name: String($0)) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func configFilePath() async throws -> String {
        let output = try await runCapture(arguments: ["config", "file"])
        let lines = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        if let path = lines.last(where: { $0.hasPrefix("/") }) {
            return path
        }

        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/rclone/rclone.conf")
            .path
    }

    func run(
        job: SyncJob,
        remoteName: String,
        maxTransferBytes: Int64?,
        processHandle: RcloneProcessHandle?,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let destination = "\(remoteName)\(job.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        var arguments = [
            job.mode.rcloneCommand,
            job.localPath,
            destination,
            "--progress",
            "--stats",
            "5s",
            "--fast-list",
            "--transfers",
            "\(job.transfers)",
            "--checkers",
            "\(job.checkers)",
            "--drive-chunk-size",
            "256M"
        ]

        if let maxTransferBytes {
            arguments.append(contentsOf: [
                "--max-transfer",
                "\(maxTransferBytes)",
                "--cutoff-mode",
                "soft"
            ])
        }

        if job.dryRun {
            arguments.append("--dry-run")
        }

        return try await runStreaming(arguments: arguments, processHandle: processHandle, onOutput: onOutput)
    }

    func listFolders(remoteName: String, path: String) async throws -> [RemoteFolder] {
        let cleanedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let remotePath = cleanedPath.isEmpty ? remoteName : "\(remoteName)\(cleanedPath)"
        let output = try await runCapture(arguments: ["lsf", remotePath, "--dirs-only"])

        return output
            .split(separator: "\n")
            .map { rawName in
                let name = String(rawName).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let childPath = cleanedPath.isEmpty ? name : "\(cleanedPath)/\(name)"
                return RemoteFolder(name: name, path: childPath)
            }
            .filter { !$0.name.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func runCapture(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = rcloneURL()
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: ServiceError.launchFailed(output.isEmpty ? "rclone exited \(process.terminationStatus)." : output))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ServiceError.launchFailed("Could not launch rclone. Install it with Homebrew or set it at /opt/homebrew/bin/rclone."))
            }
        }
    }

    private func runStreaming(
        arguments: [String],
        processHandle: RcloneProcessHandle?,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = rcloneURL()
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                onOutput(chunk)
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                processHandle?.set(nil)
                continuation.resume(returning: process.terminationStatus)
            }

            do {
                try process.run()
                processHandle?.set(process)
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                processHandle?.set(nil)
                continuation.resume(throwing: ServiceError.launchFailed("Could not launch rclone. Install it with Homebrew or set it at /opt/homebrew/bin/rclone."))
            }
        }
    }

    private func rcloneURL() -> URL {
        let candidates = [
            "/opt/homebrew/bin/rclone",
            "/usr/local/bin/rclone",
            "/usr/bin/rclone"
        ]

        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }

        return URL(fileURLWithPath: "/opt/homebrew/bin/rclone")
    }
}
