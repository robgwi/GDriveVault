import AppKit
import Foundation

@MainActor
final class SyncCoordinator: ObservableObject {
    @Published var remotes: [RcloneRemote] = []
    @Published var job = SyncJob.sample
    @Published var runs: [SyncRun] = []
    @Published var statusMessage = "Ready"
    @Published var isRefreshing = false
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var isProfileEditorPresented = false
    @Published var isLoadingProfiles = false
    @Published var isSavingProfiles = false
    @Published var isConfigWizardPresented = false
    @Published var isRemoteBrowserPresented = false
    @Published var isLoadingRemoteFolders = false
    @Published var configPath = ""
    @Published var profileDrafts: [RcloneProfileDraft] = []
    @Published var configSession = RcloneConfigSession()
    @Published var browserRemoteName = ""
    @Published var browserPath = ""
    @Published var remoteFolders: [RemoteFolder] = []
    @Published var accountUsages: [AccountUsage] = []
    @Published var savedJobs: [SyncJob] = []
    @Published var selectedJobID: SyncJob.ID?
    @Published var runningJobID: SyncJob.ID?
    @Published var hasRunnableJob = false
    @Published var interruptedRun: InterruptedRun?

    private let rclone = RcloneService()
    private let configStore = RcloneConfigStore()
    private let usageStore = UsageStore()
    private let jobStore = SyncJobStore()
    private let backupStore = BackupStore()
    private let recoveryStore = RunRecoveryStore()
    private let logStore = RunLogStore()
    private var runTask: Task<Void, Never>?
    private var activeProcessHandle: RcloneProcessHandle?
    private var shouldCancelRun = false

    init() {
        refreshUsage()
        loadSavedJobs()
        loadInterruptedRun()
    }

    func loadSavedJobs() {
        Task {
            let loaded = await jobStore.load()
            await MainActor.run {
                savedJobs = loaded
            }
        }
    }

    var hasActiveJob: Bool {
        selectedJobID != nil
    }

    func loadInterruptedRun() {
        Task {
            let recovered = await recoveryStore.load()
            await MainActor.run {
                guard let recovered else { return }
                interruptedRun = recovered
                job = recovered.job
                hasRunnableJob = true
                selectedJobID = nil
                statusMessage = "Resume available for '\(recovered.job.name)'."
            }
        }
    }

    func selectJob(_ savedJob: SyncJob) {
        guard !isRunning else { return }
        selectedJobID = savedJob.id
        job = savedJob
        hasRunnableJob = true
        statusMessage = "Loaded sync job '\(savedJob.name)'."
    }

    func runJob(_ savedJob: SyncJob) {
        guard !isRunning else { return }
        job = savedJob
        hasRunnableJob = true
        selectedJobID = nil
        start()
    }

    func newJob() {
        guard !isRunning else { return }
        var newJob = SyncJob.sample
        newJob.id = UUID()
        newJob.name = uniqueJobName(base: "New sync")
        newJob.selectedRemoteNames = []
        selectedJobID = newJob.id
        job = newJob
        hasRunnableJob = true
        runningJobID = nil
        runs = []
        interruptedRun = nil
        Task {
            await recoveryStore.clear()
        }
        statusMessage = "Created a new unsaved sync job."
    }

    func saveCurrentJob() {
        let savedName = job.name
        var jobs = savedJobs
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
        jobs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        savedJobs = jobs
        persistJobs()
        selectedJobID = nil
        hasRunnableJob = false
        statusMessage = "Saved sync profile '\(savedName)'."
    }

    func duplicateCurrentJob() {
        guard !isRunning else { return }
        var copy = job
        copy.id = UUID()
        copy.name = uniqueJobName(base: "\(job.name) copy")
        job = copy
        selectedJobID = copy.id
        saveCurrentJob()
    }

    func deleteSelectedJob() {
        guard !isRunning, let selectedJobID else { return }
        savedJobs.removeAll { $0.id == selectedJobID }
        persistJobs()

        if let first = savedJobs.first {
            self.selectedJobID = first.id
            job = first
            hasRunnableJob = true
        } else {
            self.selectedJobID = nil
            job = SyncJob.sample
            hasRunnableJob = false
        }

        statusMessage = "Deleted sync job."
    }

    func refreshRemotes() {
        isRefreshing = true
        statusMessage = "Loading rclone remotes..."

        Task {
            do {
                let loaded = try await rclone.listRemotes()
                remotes = loaded
                ensureUsageRows(for: loaded)
                if job.selectedRemoteNames.isEmpty {
                    job.selectedRemoteNames = Set(loaded.prefix(2).map(\.name))
                }
                statusMessage = loaded.isEmpty ? "No rclone remotes found." : "Loaded \(loaded.count) remotes."
            } catch {
                statusMessage = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    func toggleRemote(_ remote: RcloneRemote) {
        if job.selectedRemoteNames.contains(remote.name) {
            job.selectedRemoteNames.remove(remote.name)
            if browserRemoteName == remote.name {
                browserRemoteName = firstSelectedRemoteName() ?? ""
            }
        } else {
            job.selectedRemoteNames.insert(remote.name)
            if browserRemoteName.isEmpty {
                browserRemoteName = remote.name
            }
        }
    }

    func usage(for remoteName: String) -> AccountUsage {
        accountUsages.first(where: { $0.remoteName == remoteName }) ?? AccountUsage(
            remoteName: remoteName,
            dateKey: UsageStore.todayKey(),
            bytesTransferred: 0
        )
    }

    func resetUsage(for remoteName: String) {
        Task {
            await usageStore.reset(remoteName: remoteName)
            await MainActor.run {
                refreshUsage()
                statusMessage = "Reset usage for \(remoteName)."
            }
        }
    }

    func resetAllUsage() {
        Task {
            await usageStore.resetAll()
            await MainActor.run {
                refreshUsage()
                statusMessage = "Reset all account usage."
            }
        }
    }

    func backupSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SkyVault Backup \(backupStamp()).skyvault-backup.json"
        panel.prompt = "Backup"
        panel.message = "Export SkyVault sync profiles, account usage, and rclone profile settings."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        statusMessage = "Creating backup..."

        Task {
            do {
                let rawConfig = try await configStore.rawConfig(using: rclone)
                let backup = SkyVaultBackup(
                    schemaVersion: 1,
                    createdAt: Date(),
                    rcloneConfigPath: rawConfig.path,
                    rcloneConfigContents: rawConfig.contents,
                    syncJobs: savedJobs,
                    accountUsages: accountUsages
                )
                try await backupStore.write(backup, to: url)
                await MainActor.run {
                    statusMessage = "Backup saved to \(url.lastPathComponent)."
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func restoreSettings() {
        guard !isRunning else {
            statusMessage = "Stop the active transfer before restoring a backup."
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Restore"
        panel.message = "Choose a SkyVault backup file to restore."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        statusMessage = "Restoring backup..."

        Task {
            do {
                let backup = try await backupStore.read(from: url)
                let targetPath = try await rclone.configFilePath()
                try await configStore.restoreRawConfig(backup.rcloneConfigContents, to: targetPath)
                await jobStore.save(backup.syncJobs)
                await usageStore.save(backup.accountUsages)

                await MainActor.run {
                    savedJobs = backup.syncJobs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    accountUsages = backup.accountUsages
                    selectedJobID = nil
                    runningJobID = nil
                    hasRunnableJob = false
                    job = SyncJob.sample
                    runs = []
                    statusMessage = "Restored backup from \(url.lastPathComponent)."
                    refreshRemotes()
                    loadProfiles()
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func chooseLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"

        if panel.runModal() == .OK, let url = panel.url {
            job.localPath = url.path
        }
    }

    func openProfileEditor() {
        isProfileEditorPresented = true
        loadProfiles()
    }

    func loadProfiles() {
        isLoadingProfiles = true
        statusMessage = "Loading rclone config..."

        Task {
            do {
                let document = try await configStore.load(using: rclone)
                configPath = document.path
                profileDrafts = document.profiles
                statusMessage = "Loaded rclone config."
            } catch {
                statusMessage = error.localizedDescription
            }
            isLoadingProfiles = false
        }
    }

    func saveProfiles() {
        isSavingProfiles = true
        statusMessage = "Saving rclone config..."

        Task {
            do {
                let document = RcloneConfigDocument(path: configPath, profiles: profileDrafts)
                try await configStore.save(document)
                statusMessage = "Saved rclone config."
                isProfileEditorPresented = false
                refreshRemotes()
            } catch {
                statusMessage = error.localizedDescription
            }
            isSavingProfiles = false
        }
    }

    func importProfiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose an rclone config file to import."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isLoadingProfiles = true
        statusMessage = "Importing \(url.lastPathComponent)..."

        Task {
            do {
                let imported = try await configStore.loadProfiles(from: url)
                let prepared = uniqued(importedProfiles: imported)
                profileDrafts.append(contentsOf: prepared)
                statusMessage = "Imported \(prepared.count) profile\(prepared.count == 1 ? "" : "s"). Review and save to apply."
            } catch {
                statusMessage = error.localizedDescription
            }
            isLoadingProfiles = false
        }
    }

    func addProfile() {
        let existingNames = Set(profileDrafts.map { $0.name.lowercased() })
        var index = profileDrafts.count + 1
        var name = "gdrive\(index)"
        while existingNames.contains(name.lowercased()) {
            index += 1
            name = "gdrive\(index)"
        }

        profileDrafts.append(RcloneProfileDraft(name: name, entries: [
            RcloneConfigEntry(key: "type", value: "drive"),
            RcloneConfigEntry(key: "scope", value: "drive")
        ]))
    }

    func deleteProfile(_ profile: RcloneProfileDraft) {
        profileDrafts.removeAll { $0.id == profile.id }
    }

    func addEntry(to profile: RcloneProfileDraft) {
        guard let index = profileDrafts.firstIndex(where: { $0.id == profile.id }) else { return }
        profileDrafts[index].entries.append(RcloneConfigEntry(key: "", value: ""))
    }

    private func uniqued(importedProfiles: [RcloneProfileDraft]) -> [RcloneProfileDraft] {
        var usedNames = Set(profileDrafts.map { $0.name.lowercased() })

        return importedProfiles.map { profile in
            var copy = profile
            let baseName = profile.name.isEmpty ? "imported" : profile.name
            var candidate = baseName
            var index = 2

            while usedNames.contains(candidate.lowercased()) {
                candidate = "\(baseName)-imported-\(index)"
                index += 1
            }

            copy.name = candidate
            usedNames.insert(candidate.lowercased())
            return copy
        }
    }

    func openConfigWizard() {
        isConfigWizardPresented = true
        configSession.start { [weak self] in
            self?.loadProfiles()
            self?.refreshRemotes()
        }
    }

    func closeConfigWizard() {
        configSession.stop()
        isConfigWizardPresented = false
        loadProfiles()
        refreshRemotes()
    }

    func openRemoteBrowser() {
        browserRemoteName = firstSelectedRemoteName() ?? remotes.first?.name ?? ""
        browserPath = job.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        isRemoteBrowserPresented = true
        loadRemoteFolders()
    }

    func firstSelectedRemoteName() -> String? {
        remotes.first(where: { job.selectedRemoteNames.contains($0.name) })?.name
    }

    func selectBrowserRemote(_ remoteName: String) {
        browserRemoteName = remoteName
        browserPath = ""
        loadRemoteFolders()
    }

    func openRemoteFolder(_ folder: RemoteFolder) {
        browserPath = folder.path
        loadRemoteFolders()
    }

    func goToParentRemoteFolder() {
        guard !browserPath.isEmpty else { return }
        var parts = browserPath.split(separator: "/").map(String.init)
        parts.removeLast()
        browserPath = parts.joined(separator: "/")
        loadRemoteFolders()
    }

    func useCurrentRemoteFolder() {
        job.remotePath = browserPath
        isRemoteBrowserPresented = false
    }

    func loadRemoteFolders() {
        guard !browserRemoteName.isEmpty else {
            statusMessage = "Choose a profile before browsing Drive folders."
            remoteFolders = []
            return
        }

        isLoadingRemoteFolders = true
        statusMessage = "Loading \(browserRemoteName)\(browserPath)..."

        Task {
            do {
                remoteFolders = try await rclone.listFolders(remoteName: browserRemoteName, path: browserPath)
                statusMessage = remoteFolders.isEmpty ? "No folders found at this location." : "Loaded \(remoteFolders.count) folders."
            } catch {
                statusMessage = error.localizedDescription
                remoteFolders = []
            }
            isLoadingRemoteFolders = false
        }
    }

    func start() {
        guard !isRunning else { return }
        guard hasRunnableJob else {
            statusMessage = "Select a sync profile or click New before starting."
            return
        }
        beginRun(status: "Starting failover pool")
    }

    func resume() {
        guard hasRunnableJob, canResume else { return }
        beginRun(status: "Resuming sync")
    }

    var canResume: Bool {
        guard !isRunning else { return false }
        if interruptedRun != nil {
            return true
        }
        return runs.contains { run in
            switch run.state {
            case .cancelled, .failed:
                true
            case .finished(let code):
                code != 0
            case .idle, .running, .skipped:
                false
            }
        }
    }

    private func beginRun(status: String) {
        let selected = remotes.filter { job.selectedRemoteNames.contains($0.name) }
        guard !selected.isEmpty else {
            statusMessage = "Choose at least one rclone remote."
            return
        }

        shouldCancelRun = false
        runs = []
        isRunning = true
        isPaused = false
        runningJobID = job.id
        interruptedRun = InterruptedRun(job: job, startedAt: Date(), reason: status)
        statusMessage = "\(status) with \(selected.count) profiles..."

        let recovery = interruptedRun
        Task {
            if let recovery {
                await recoveryStore.save(recovery)
            }
        }

        runTask = Task {
            var completed = false
            var logSession: RunLogSession?

            do {
                logSession = try await logStore.createSession(for: job)
            } catch {
                await MainActor.run {
                    statusMessage = "Running without saved logs: \(error.localizedDescription)"
                }
            }

            for remote in selected {
                if await MainActor.run(body: { shouldCancelRun }) {
                    break
                }

                let usage = await usageStore.usage(for: remote.name)
                let remaining = usage.remainingBytes
                let logFileURL = logSession.map { session in
                    logStore.logFileURL(for: remote.name, in: session)
                }

                if !job.dryRun, remaining <= 0 {
                    await MainActor.run {
                        runs.append(SyncRun(
                            remoteName: remote.name,
                            startedAt: Date(),
                            state: .skipped(message: "750 GB quota window reached."),
                            log: "Skipped \(remote.displayName): 750 GB quota window reached.\n",
                            logFilePath: nil,
                            transferredBytes: 0,
                            maxTransferBytes: remaining,
                            progress: nil
                        ))
                    }
                    continue
                }

                await MainActor.run {
                    runs.append(SyncRun(
                        remoteName: remote.name,
                        startedAt: Date(),
                        state: .running,
                        log: "Starting \(remote.displayName) with \(job.dryRun ? "dry-run" : TransferStatsParser.formatBytes(remaining)) available in the current quota window.\n",
                        logFilePath: logFileURL?.path,
                        transferredBytes: 0,
                        maxTransferBytes: job.dryRun ? nil : remaining,
                        progress: nil
                    ))
                    statusMessage = "Running \(remote.displayName)..."
                }

                let processHandle = RcloneProcessHandle()
                await MainActor.run {
                    activeProcessHandle = processHandle
                }

                do {
                    let code = try await rclone.run(
                        job: job,
                        remoteName: remote.name,
                        maxTransferBytes: job.dryRun ? nil : remaining
                        ,
                        logFileURL: logFileURL,
                        processHandle: processHandle
                    ) { chunk in
                        Task { @MainActor in
                            self.append(chunk, to: remote.name)
                        }
                    }

                    await MainActor.run {
                        activeProcessHandle = nil
                        finish(remote.name, state: shouldCancelRun ? .cancelled : .finished(code: code))
                    }

                    if await MainActor.run(body: { shouldCancelRun }) {
                        break
                    }

                    if code == 0 {
                        completed = true
                        break
                    }
                } catch {
                    await MainActor.run {
                        activeProcessHandle = nil
                        finish(remote.name, state: .failed(message: error.localizedDescription))
                    }
                }
            }

            let cancelled = await MainActor.run(body: { shouldCancelRun })
            let finalStatus = cancelled ? "Transfer cancelled." : (completed ? "Sync completed." : "Failover pool exhausted.")
            await MainActor.run {
                activeProcessHandle = nil
                runTask = nil
                isRunning = false
                isPaused = false
                runningJobID = nil
                if completed {
                    interruptedRun = nil
                    Task {
                        await recoveryStore.clear()
                    }
                } else {
                    interruptedRun = InterruptedRun(job: job, startedAt: Date(), reason: cancelled ? "Cancelled" : "Incomplete")
                    if let interruptedRun {
                        Task {
                            await recoveryStore.save(interruptedRun)
                        }
                    }
                }
                statusMessage = finalStatus
                let finalRuns = runs
                if let logSession {
                    Task {
                        try? await logStore.writeSummary(session: logSession, job: job, runs: finalRuns, finalStatus: finalStatus)
                    }
                }
            }
        }
    }

    func stop() {
        pause()
    }

    func cancelJob() {
        guard isRunning else { return }
        shouldCancelRun = true
        isPaused = false
        statusMessage = "Cancelling current transfer..."
        activeProcessHandle?.terminate()
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        activeProcessHandle?.pause()
        isPaused = true
        statusMessage = "Transfer paused. Keep SkyVault open to resume the active partial upload."
    }

    func continuePausedRun() {
        guard isRunning, isPaused else { return }
        activeProcessHandle?.resume()
        isPaused = false
        statusMessage = "Transfer resumed."
    }

    private func append(_ chunk: String, to remoteName: String) {
        guard let index = runs.firstIndex(where: { $0.remoteName == remoteName }) else { return }
        runs[index].log.append(chunk)
        if let progress = TransferStatsParser.progress(in: chunk) {
            runs[index].progress = progress
        }
        if !job.dryRun, let transferredBytes = TransferStatsParser.transferredBytes(in: chunk) {
            let delta = transferredBytes - runs[index].transferredBytes
            runs[index].transferredBytes = max(runs[index].transferredBytes, transferredBytes)
            if delta > 0 {
                addUsage(delta, to: remoteName)
            }
        }
        if runs[index].log.count > 24_000 {
            runs[index].log.removeFirst(runs[index].log.count - 24_000)
        }
    }

    private func finish(_ remoteName: String, state: RunState) {
        guard let index = runs.firstIndex(where: { $0.remoteName == remoteName }) else { return }
        runs[index].state = state
    }

    private func refreshUsage() {
        Task {
            let loaded = await usageStore.load()
            await MainActor.run {
                accountUsages = loaded
                ensureUsageRows(for: remotes)
            }
        }
    }

    private func ensureUsageRows(for remotes: [RcloneRemote]) {
        let existingNames = Set(accountUsages.map(\.remoteName))
        let missing = remotes
            .filter { !existingNames.contains($0.name) }
            .map { AccountUsage(remoteName: $0.name, dateKey: UsageStore.todayKey(), bytesTransferred: 0) }
        accountUsages.append(contentsOf: missing)
        accountUsages.sort { $0.remoteName.localizedCaseInsensitiveCompare($1.remoteName) == .orderedAscending }
    }

    private func addUsage(_ bytes: Int64, to remoteName: String) {
        if let index = accountUsages.firstIndex(where: { $0.remoteName == remoteName }) {
            accountUsages[index].bytesTransferred += bytes
        } else {
            accountUsages.append(AccountUsage(remoteName: remoteName, dateKey: UsageStore.todayKey(), bytesTransferred: bytes))
        }

        Task {
            await usageStore.addTransferredBytes(bytes, for: remoteName)
        }
    }

    private func persistJobs() {
        let jobs = savedJobs
        Task {
            await jobStore.save(jobs)
        }
    }

    private func uniqueJobName(base: String) -> String {
        let existingNames = Set(savedJobs.map { $0.name.lowercased() })
        if !existingNames.contains(base.lowercased()) {
            return base
        }

        var index = 2
        var candidate = "\(base) \(index)"
        while existingNames.contains(candidate.lowercased()) {
            index += 1
            candidate = "\(base) \(index)"
        }
        return candidate
    }

    private func backupStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter.string(from: Date())
    }
}
