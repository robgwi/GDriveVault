import AppKit
import Foundation

private enum GoogleChatEvent {
    case started(job: SyncJob, destinations: [String])
    case finished(job: SyncJob, status: String, runSummaries: [String])

    var message: String {
        switch self {
        case .started(let job, let destinations):
            let destinationLines = destinations.map { "• \($0)" }.joined(separator: "\n")
            return """
            GDriveVault started: \(job.name)
            Direction: \(job.direction.label)
            Mode: \(job.mode.label)\(job.dryRun ? " (dry run)" : "")
            \(job.direction == .download ? "Local destination" : "Local source"): \(job.localPath)
            \(job.direction == .download ? "Drive sources" : "Drive destinations"):
            \(destinationLines)
            """
        case .finished(let job, let status, let runSummaries):
            let runLines = runSummaries.map { "• \($0)" }.joined(separator: "\n")

            return """
            GDriveVault finished: \(job.name)
            Status: \(status)
            \(job.direction == .download ? "Drive source" : "Drive destination"): \(teamDestinationPath(for: job))
            \(runLines)
            """
        }
    }

    private func teamDestinationPath(for job: SyncJob) -> String {
        let root = job.remoteRootName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? job.remoteRootName!.trimmingCharacters(in: .whitespacesAndNewlines) : "MrHandPay"
        let path = job.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? root : "\(root)/\(path)"
    }
}

private enum RestoreSettingsError: LocalizedError {
    case activeTransfer
    case missingBackupID

    var errorDescription: String? {
        switch self {
        case .activeTransfer:
            "Stop the active transfer before restoring a settings backup."
        case .missingBackupID:
            "The restore settings command did not include a backup_id."
        }
    }
}

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
    @Published var isDownloadBrowserPresented = false
    @Published var isDownloadManagerPresented = false
    @Published var isLoadingRemoteFolders = false
    @Published var isLoadingRemoteItems = false
    @Published var configPath = ""
    @Published var profileDrafts: [RcloneProfileDraft] = []
    @Published var configSession = RcloneConfigSession()
    @Published var browserRemoteName = ""
    @Published var browserPath = ""
    @Published var remoteFolders: [RemoteFolder] = []
    @Published var remoteItems: [RemoteItem] = []
    @Published var selectedRemoteItemIDs: Set<RemoteItem.ID> = []
    @Published var downloadLocalPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads/GDriveVault Downloads", isDirectory: true)
        .path
    @Published var accountUsages: [AccountUsage] = []
    @Published var savedJobs: [SyncJob] = []
    @Published var selectedJobID: SyncJob.ID?
    @Published var runningJobID: SyncJob.ID?
    @Published var hasRunnableJob = false
    @Published var interruptedRun: InterruptedRun?
    @Published var isCheckingForUpdates = false
    @Published var updateNotification: UpdateNotification?
    @Published var isChatSettingsPresented = false
    @Published var googleChatSettings = GoogleChatSettings.disabled
    @Published var isTestingGoogleChat = false
    @Published var isRemoteControlSettingsPresented = false
    @Published var remoteControlSettings = RemoteControlSettings.disabled
    @Published var isRegisteringRemoteControl = false
    @Published var isAutomaticRemoteRegistration = false
    @Published var isTestingRemoteControl = false
    @Published var remoteControlStatus = "Not connected"
    @Published var isUploadingSettingsBackup = false
    @Published var isLicenseLocked = false
    @Published var isRunningBandwidthTest = false
    @Published var latestBandwidthTest: BandwidthTestResult?
    @Published var droppedUploadItems: [DroppedUploadItem] = []
    @Published var stageDroppedUploads = false
    @Published var isPreparingDroppedUpload = false

    var requiresRegistration: Bool {
        isLicenseLocked || !remoteControlSettings.isRegistered
    }

    private let rclone = RcloneService()
    private let configStore = RcloneConfigStore()
    private let usageStore = UsageStore()
    private let jobStore = SyncJobStore()
    private let backupStore = BackupStore()
    private let recoveryStore = RunRecoveryStore()
    private let logStore = RunLogStore()
    private let updateChecker = UpdateChecker()
    private let chatSettingsStore = GoogleChatSettingsStore()
    private let googleChat = GoogleChatService()
    private let remoteControlSettingsStore = RemoteControlSettingsStore()
    private let remoteControlService = RemoteControlService()
    private let bandwidthTestService = BandwidthTestService()
    private let bandwidthTestStore = BandwidthTestStore()
    private let updateInstaller = UpdateInstaller()
    private var runTask: Task<Void, Never>?
    private var remoteControlTask: Task<Void, Never>?
    private var pendingRegistrationTask: Task<Void, Never>?
    private var activeProcessHandle: RcloneProcessHandle?
    private var shouldCancelRun = false
    private var hasCheckedForUpdates = false
    private var didUploadSettingsBackupForCurrentConnection = false
    private var completedFileBufferByRemote: [String: Set<String>] = [:]
    private var lastChatProgressSentAtByRemote: [String: Date] = [:]
    private var lastChatProgressPercentByRemote: [String: Int] = [:]
    private var recentRemoteChanges: [RemoteControlChange] = []
    private var changeKeys = Set<String>()
    private var filesAdded = 0
    private var filesUpdated = 0
    private var filesDeleted = 0
    private var bytesAdded: Int64 = 0
    private var bytesUpdated: Int64 = 0

    init() {
        refreshUsage()
        loadSavedJobs()
        loadInterruptedRun()
        loadGoogleChatSettings()
        loadRemoteControlSettings()
        loadLatestBandwidthTest()
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

    func addDroppedUploadURLs(_ urls: [URL]) {
        let items = urls
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { url in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                return DroppedUploadItem(url: url, isDirectory: isDirectory.boolValue)
            }

        droppedUploadItems = uniquedDroppedItems(droppedUploadItems + items)
        if droppedUploadItems.count > 1 {
            stageDroppedUploads = true
        }
        statusMessage = droppedUploadItems.isEmpty ? "Drop files or folders to upload." : "Ready to upload \(droppedUploadItems.count) dropped item\(droppedUploadItems.count == 1 ? "" : "s")."
    }

    func clearDroppedUploads() {
        droppedUploadItems = []
        statusMessage = "Cleared dropped uploads."
    }

    func uploadDroppedItems() {
        guard !isRunning, !isRunningBandwidthTest, !isPreparingDroppedUpload else { return }
        guard ensureLicenseAllowsOperation() else { return }
        guard !droppedUploadItems.isEmpty else {
            statusMessage = "Drop a file or folder before uploading."
            return
        }
        guard let baseJob = dropUploadBaseJob() else {
            statusMessage = savedJobs.isEmpty ? "Create and save a sync profile before drag-and-drop uploads." : "Choose a sync profile before drag-and-drop uploads."
            return
        }

        isPreparingDroppedUpload = true
        statusMessage = "Preparing dropped upload..."
        let items = droppedUploadItems
        let shouldStage = stageDroppedUploads || items.count > 1

        Task {
            do {
                let uploadJob = try prepareDroppedUploadJob(baseJob: baseJob, items: items, shouldStage: shouldStage)
                await MainActor.run {
                    job = uploadJob
                    hasRunnableJob = true
                    selectedJobID = nil
                    isPreparingDroppedUpload = false
                    droppedUploadItems = []
                    start()
                }
            } catch {
                await MainActor.run {
                    isPreparingDroppedUpload = false
                    statusMessage = "Could not prepare dropped upload: \(error.localizedDescription)"
                }
            }
        }
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

    func checkForUpdates(showUpToDate: Bool) {
        if isCheckingForUpdates { return }
        if !showUpToDate, hasCheckedForUpdates { return }

        isCheckingForUpdates = true
        hasCheckedForUpdates = true
        if showUpToDate {
            statusMessage = "Checking for updates..."
        }

        Task {
            do {
                let result = try await updateChecker.check(currentVersion: AppVersion.current, settings: remoteControlSettings)
                await MainActor.run {
                    isCheckingForUpdates = false
                    if result.hasUpdate {
                        updateNotification = UpdateNotification(
                            title: "GDriveVault \(result.latestVersion) is available",
                            message: "You are running \(result.currentVersion). Install the latest build from GDriveVault Control.",
                            actionTitle: "Install Update",
                            actionURL: result.releaseURL,
                            installRequest: result.installRequest
                        )
                        statusMessage = "Update available: \(result.latestVersion)."
                    } else if showUpToDate {
                        updateNotification = UpdateNotification(
                            title: "GDriveVault is up to date",
                            message: "You are running version \(result.currentVersion).",
                            actionTitle: nil,
                            actionURL: nil
                        )
                        statusMessage = "GDriveVault is up to date."
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingForUpdates = false
                    if showUpToDate {
                        updateNotification = UpdateNotification(
                            title: "Could not check for updates",
                            message: error.localizedDescription,
                            actionTitle: nil,
                            actionURL: nil
                        )
                    }
                    statusMessage = showUpToDate ? "Update check failed." : statusMessage
                }
            }
        }
    }

    func installUpdateFromNotification(_ notification: UpdateNotification) {
        guard let request = notification.installRequest else {
            if let url = notification.actionURL {
                NSWorkspace.shared.open(url)
            }
            return
        }
        installUpdate(request, source: "manual")
    }

    private func installLatestUpdateFromControl(payload: [String: String]) async throws {
        let request: UpdateInstallRequest
        if let rawURL = payload["download_url"] ?? payload["downloadURL"],
           let url = URL(string: rawURL),
           let version = payload["version"] ?? payload["latest"] {
            request = UpdateInstallRequest(version: version, downloadURL: url, sha256: payload["sha256"])
        } else {
            let result = try await updateChecker.check(currentVersion: AppVersion.current, settings: remoteControlSettings)
            guard result.hasUpdate else {
                await MainActor.run {
                    statusMessage = "Remote update ignored: GDriveVault is already up to date."
                }
                return
            }
            request = result.installRequest
        }

        await MainActor.run {
            installUpdate(request, source: "remote")
        }
    }

    private func installUpdate(_ request: UpdateInstallRequest, source: String) {
        guard !isRunning else {
            statusMessage = "Update blocked while a transfer is running."
            return
        }
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        statusMessage = source == "remote" ? "Installing forced update \(request.version)..." : "Installing update \(request.version)..."

        Task {
            do {
                let helperURL = try await updateInstaller.prepareInstall(request)
                try await updateInstaller.launchInstaller(helperURL: helperURL)
                await MainActor.run {
                    isCheckingForUpdates = false
                    statusMessage = "Update installer launched. GDriveVault will restart."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NSApp.terminate(nil)
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingForUpdates = false
                    statusMessage = "Update install failed: \(error.localizedDescription)"
                    updateNotification = UpdateNotification(
                        title: "Update install failed",
                        message: error.localizedDescription,
                        actionTitle: nil,
                        actionURL: nil
                    )
                }
            }
        }
    }

    func loadGoogleChatSettings() {
        Task {
            let loaded = await chatSettingsStore.load()
            await MainActor.run {
                googleChatSettings = loaded
            }
        }
    }

    func openGoogleChatSettings() {
        isChatSettingsPresented = true
    }

    func saveGoogleChatSettings() {
        let settings = googleChatSettings
        Task {
            await chatSettingsStore.save(settings)
            await MainActor.run {
                isChatSettingsPresented = false
                statusMessage = settings.isConfigured ? "Saved Google Chat notifications." : "Google Chat notifications disabled."
            }
        }
    }

    func testGoogleChat() {
        guard !isTestingGoogleChat else { return }
        isTestingGoogleChat = true
        let settings = googleChatSettings

        Task {
            do {
                try await googleChat.send("GDriveVault test message: Google Chat notifications are connected.", settings: settings)
                await MainActor.run {
                    isTestingGoogleChat = false
                    statusMessage = "Sent Google Chat test message."
                }
            } catch {
                await MainActor.run {
                    isTestingGoogleChat = false
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func loadRemoteControlSettings() {
        Task {
            let loaded = await remoteControlSettingsStore.load()
            await MainActor.run {
                remoteControlSettings = loaded
                if loaded.isPendingApproval {
                    remoteControlStatus = "Waiting for dashboard approval."
                } else {
                    remoteControlStatus = loaded.isRegistered ? "Remote control ready." : "Not connected"
                }
                if loaded.isRegistered {
                    startRemoteControlLoopIfNeeded()
                } else if loaded.isPendingApproval {
                    isRemoteControlSettingsPresented = true
                    startPendingApprovalPollingIfNeeded()
                } else {
                    isRemoteControlSettingsPresented = true
                    autoRegisterRemoteControlIfNeeded(reason: "startup")
                }
            }
        }
    }

    func openRemoteControlSettings() {
        isRemoteControlSettingsPresented = true
    }

    func saveRemoteControlSettings() {
        let settings = remoteControlSettings.lockedToProductionServer
        remoteControlSettings = settings
        Task {
            await remoteControlSettingsStore.save(settings)
            await MainActor.run {
                isRemoteControlSettingsPresented = false
                remoteControlStatus = "Remote control enabled."
                didUploadSettingsBackupForCurrentConnection = false
                if !settings.isRegistered {
                    autoRegisterRemoteControlIfNeeded(reason: "settings saved")
                } else {
                    startRemoteControlLoopIfNeeded()
                }
            }
        }
    }

    func registerRemoteControlDevice() {
        registerRemoteControlDevice(automatic: false)
    }

    private func registerRemoteControlDevice(automatic: Bool) {
        guard !isRegisteringRemoteControl else { return }
        remoteControlSettings = remoteControlSettings.lockedToProductionServer
        isRegisteringRemoteControl = true
        isAutomaticRemoteRegistration = automatic
        isLicenseLocked = false
        if remoteControlSettings.isPendingApproval {
            remoteControlStatus = automatic ? "Checking dashboard approval..." : "Checking approval..."
        } else if remoteControlSettings.hasLicenseKey {
            remoteControlStatus = automatic ? "Auto-registering with control server..." : "Registering with control server..."
        } else {
            remoteControlStatus = automatic ? "Requesting dashboard approval..." : "Requesting approval..."
        }
        let settings = remoteControlSettings

        Task {
            do {
                let registered = try await remoteControlService.register(settings: settings)
                await remoteControlSettingsStore.save(registered)
                await MainActor.run {
                    remoteControlSettings = registered
                    isRegisteringRemoteControl = false
                    isAutomaticRemoteRegistration = false
                    didUploadSettingsBackupForCurrentConnection = false
                    if registered.isPendingApproval {
                        remoteControlStatus = "Waiting for dashboard approval or license pickup."
                        isRemoteControlSettingsPresented = true
                        startPendingApprovalPollingIfNeeded()
                    } else {
                        remoteControlStatus = registered.hasLicenseKey ? "Registered \(registered.deviceName)." : "Registered \(registered.deviceName)."
                        isLicenseLocked = false
                        isRemoteControlSettingsPresented = false
                        pendingRegistrationTask?.cancel()
                        pendingRegistrationTask = nil
                        startRemoteControlLoopIfNeeded()
                    }
                }
            } catch {
                await MainActor.run {
                    isRegisteringRemoteControl = false
                    isAutomaticRemoteRegistration = false
                    remoteControlStatus = error.localizedDescription
                }
            }
        }
    }

    private func autoRegisterRemoteControlIfNeeded(reason: String) {
        guard !remoteControlSettings.isRegistered,
              !remoteControlSettings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !remoteControlSettings.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        remoteControlStatus = "License \(reason): registering this Mac..."
        registerRemoteControlDevice(automatic: true)
    }

    private func startPendingApprovalPollingIfNeeded() {
        pendingRegistrationTask?.cancel()
        guard remoteControlSettings.isPendingApproval else { return }
        pendingRegistrationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let seconds = await MainActor.run { max(5, self.remoteControlSettings.pollIntervalSeconds) }
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                await MainActor.run {
                    guard self.remoteControlSettings.isPendingApproval, !self.isRegisteringRemoteControl else { return }
                    self.registerRemoteControlDevice(automatic: true)
                }
            }
        }
    }

    func testRemoteControlConnection() {
        guard !isTestingRemoteControl else { return }
        isTestingRemoteControl = true
        remoteControlStatus = "Testing remote control..."
        let settings = remoteControlSettings
        let heartbeat = makeRemoteControlHeartbeat()

        Task {
            do {
                try await remoteControlService.sendHeartbeat(heartbeat, settings: settings)
                await MainActor.run {
                    isTestingRemoteControl = false
                    remoteControlStatus = "Remote control connected."
                }
            } catch {
                await MainActor.run {
                    isTestingRemoteControl = false
                    remoteControlStatus = error.localizedDescription
                }
            }
        }
    }

    func loadLatestBandwidthTest() {
        Task {
            let loaded = await bandwidthTestStore.load()
            await MainActor.run {
                latestBandwidthTest = loaded
            }
        }
    }

    func runBandwidthTest() {
        guard !isRunningBandwidthTest else { return }
        isRunningBandwidthTest = true
        statusMessage = "Testing internet bandwidth..."

        Task {
            do {
                let result = try await bandwidthTestService.run()
                await bandwidthTestStore.save(result)
                await MainActor.run {
                    latestBandwidthTest = result
                    isRunningBandwidthTest = false
                    statusMessage = "Bandwidth test complete: \(result.displaySpeed)."
                }
            } catch {
                await MainActor.run {
                    isRunningBandwidthTest = false
                    statusMessage = "Bandwidth test failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func runBandwidthTestThenBegin(status: String) {
        isRunningBandwidthTest = true
        statusMessage = "Testing internet bandwidth before sync..."

        Task {
            do {
                let result = try await bandwidthTestService.run()
                await bandwidthTestStore.save(result)
                await MainActor.run {
                    latestBandwidthTest = result
                    isRunningBandwidthTest = false
                    beginRun(status: status)
                }
            } catch {
                await MainActor.run {
                    isRunningBandwidthTest = false
                    statusMessage = "Sync not started. Bandwidth test failed: \(error.localizedDescription)"
                }
            }
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
        panel.nameFieldStringValue = "GDriveVault Backup \(backupStamp()).gdrivevault-backup.json"
        panel.prompt = "Backup"
        panel.message = "Export GDriveVault sync profiles, account usage, and rclone profile settings."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        statusMessage = "Creating backup..."

        Task {
            do {
                let backup = try await makeSettingsBackup()
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

    func uploadSettingsBackupToControlServer() {
        uploadSettingsBackupToControlServer(automatic: false)
    }

    private func uploadSettingsBackupToControlServer(automatic: Bool) {
        guard !isUploadingSettingsBackup else { return }
        guard remoteControlSettings.isRegistered else {
            if !automatic {
                statusMessage = "Register this Mac with GDriveVault Control before uploading a settings backup."
            }
            return
        }

        isUploadingSettingsBackup = true
        if !automatic {
            statusMessage = "Uploading settings backup to GDriveVault Control..."
        }
        let settings = remoteControlSettings

        Task {
            do {
                let backup = try await makeSettingsBackup()
                let backupID = try await remoteControlService.uploadSettingsBackup(backup, settings: settings)
                await MainActor.run {
                    isUploadingSettingsBackup = false
                    didUploadSettingsBackupForCurrentConnection = true
                    if automatic {
                        remoteControlStatus = "Connected. Settings backup \(backupID) uploaded."
                    } else {
                        statusMessage = "Uploaded settings backup \(backupID) to GDriveVault Control."
                    }
                }
            } catch {
                await MainActor.run {
                    isUploadingSettingsBackup = false
                    if automatic {
                        remoteControlStatus = "Connected. Settings backup upload failed: \(error.localizedDescription)"
                    } else {
                        statusMessage = "Settings backup upload failed: \(error.localizedDescription)"
                    }
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
        panel.message = "Choose a GDriveVault backup file to restore."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        statusMessage = "Restoring backup..."

        Task {
            do {
                let backup = try await backupStore.read(from: url)
                try await applySettingsBackup(backup, status: "Restored backup from \(url.lastPathComponent).")
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func restoreSettingsBackupFromControlServer(backupID: String, settings: RemoteControlSettings) async throws {
        guard !isRunning else {
            throw RestoreSettingsError.activeTransfer
        }

        let backup = try await remoteControlService.downloadSettingsBackup(backupID: backupID, settings: settings)
        try await applySettingsBackup(backup, status: "Restored settings backup \(backupID) from GDriveVault Control.")
    }

    private func applySettingsBackup(_ backup: GDriveVaultBackup, status: String) async throws {
        let targetPath = try await rclone.configFilePath()
        try await configStore.restoreRawConfig(backup.rcloneConfigContents, to: targetPath)
        await jobStore.save(backup.syncJobs)
        await usageStore.save(backup.accountUsages)
        await chatSettingsStore.save(backup.googleChatSettings ?? .disabled)
        let restoredRemoteSettings = (backup.remoteControlSettings ?? .disabled).lockedToProductionServer
        await remoteControlSettingsStore.save(restoredRemoteSettings)

        await MainActor.run {
            savedJobs = backup.syncJobs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            accountUsages = backup.accountUsages
            googleChatSettings = backup.googleChatSettings ?? .disabled
            remoteControlSettings = restoredRemoteSettings
            didUploadSettingsBackupForCurrentConnection = false
            startRemoteControlLoopIfNeeded()
            selectedJobID = nil
            runningJobID = nil
            hasRunnableJob = false
            job = SyncJob.sample
            runs = []
            statusMessage = status
            refreshRemotes()
            loadProfiles()
        }
    }

    private func makeSettingsBackup() async throws -> GDriveVaultBackup {
        let rawConfig = try await configStore.rawConfig(using: rclone)
        return GDriveVaultBackup(
            schemaVersion: 1,
            createdAt: Date(),
            rcloneConfigPath: rawConfig.path,
            rcloneConfigContents: rawConfig.contents,
            syncJobs: savedJobs,
            accountUsages: accountUsages,
            googleChatSettings: googleChatSettings,
            remoteControlSettings: remoteControlSettings
        )
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

    func openProfileImporter() {
        isProfileEditorPresented = true
        if profileDrafts.isEmpty {
            loadProfiles()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.importProfiles()
        }
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
                if profileDrafts.isEmpty {
                    let document = try await configStore.load(using: rclone)
                    profileDrafts = document.profiles
                    configPath = document.path
                }
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

    func selectDownloadBrowserRemote(_ remoteName: String) {
        browserRemoteName = remoteName
        browserPath = ""
        remoteItems = []
        selectedRemoteItemIDs = []
        loadRemoteItems()
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

    func openDownloadBrowser() {
        browserRemoteName = firstSelectedRemoteName() ?? remotes.first?.name ?? ""
        browserPath = job.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        selectedRemoteItemIDs = []
        isDownloadBrowserPresented = true
        loadRemoteItems()
    }

    func loadRemoteItems() {
        guard !browserRemoteName.isEmpty else {
            statusMessage = "Choose a profile before browsing Drive files."
            remoteItems = []
            return
        }

        isLoadingRemoteItems = true
        statusMessage = "Loading \(browserRemoteName)\(browserPath)..."

        Task {
            do {
                let items = try await rclone.listRemoteItems(remoteName: browserRemoteName, path: browserPath)
                await MainActor.run {
                    remoteItems = items
                    selectedRemoteItemIDs = selectedRemoteItemIDs.intersection(Set(items.map(\.id)))
                    statusMessage = items.isEmpty ? "No files or folders found at this location." : "Loaded \(items.count) remote items."
                    isLoadingRemoteItems = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    remoteItems = []
                    selectedRemoteItemIDs = []
                    isLoadingRemoteItems = false
                }
            }
        }
    }

    func openDownloadFolder(_ item: RemoteItem) {
        guard item.isDirectory else { return }
        browserPath = item.path
        selectedRemoteItemIDs = []
        loadRemoteItems()
    }

    func goToParentDownloadFolder() {
        guard !browserPath.isEmpty else { return }
        var parts = browserPath.split(separator: "/").map(String.init)
        parts.removeLast()
        browserPath = parts.joined(separator: "/")
        selectedRemoteItemIDs = []
        loadRemoteItems()
    }

    func toggleRemoteItemSelection(_ item: RemoteItem) {
        if selectedRemoteItemIDs.contains(item.id) {
            selectedRemoteItemIDs.remove(item.id)
        } else {
            selectedRemoteItemIDs.insert(item.id)
        }
    }

    func chooseDownloadDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose Download Destination"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            downloadLocalPath = url.path
        }
    }

    func startSelectedRemoteDownload() {
        guard !isRunning, !isRunningBandwidthTest else { return }
        guard ensureLicenseAllowsOperation() else { return }
        let selectedItems = remoteItems.filter { selectedRemoteItemIDs.contains($0.id) }
        guard !selectedItems.isEmpty else {
            statusMessage = "Select at least one file or folder to download."
            return
        }
        guard !downloadLocalPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Choose a local download destination."
            return
        }

        let includes = selectedItems.map { item in
            item.isDirectory ? "\(item.name)/**" : item.name
        }
        let selectedRemotes = job.selectedRemoteNames.isEmpty ? Set([browserRemoteName]) : job.selectedRemoteNames
        let downloadJob = SyncJob(
            name: "Download \(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s")",
            localPath: downloadLocalPath,
            remotePath: browserPath,
            remoteRootName: job.remoteRootName,
            direction: .download,
            mode: .copy,
            selectedRemoteNames: selectedRemotes,
            transfers: job.transfers,
            checkers: job.checkers,
            dryRun: false,
            cleanupLocalPathAfterRun: nil,
            remoteIncludes: includes
        )

        job = downloadJob
        hasRunnableJob = true
        selectedJobID = nil
        isDownloadBrowserPresented = false
        isDownloadManagerPresented = true
        start()
    }

    func start() {
        guard !isRunning, !isRunningBandwidthTest else { return }
        guard ensureLicenseAllowsOperation() else { return }
        guard hasRunnableJob else {
            statusMessage = "Select a sync profile or click New before starting."
            return
        }
        runBandwidthTestThenBegin(status: "Starting failover pool")
    }

    func resume() {
        guard hasRunnableJob, canResume, !isRunningBandwidthTest else { return }
        guard ensureLicenseAllowsOperation() else { return }
        runBandwidthTestThenBegin(status: "Resuming sync")
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
        completedFileBufferByRemote = [:]
        lastChatProgressSentAtByRemote = [:]
        lastChatProgressPercentByRemote = [:]
        resetRemoteChangeTracking()
        isRunning = true
        isPaused = false
        runningJobID = job.id
        interruptedRun = InterruptedRun(job: job, startedAt: Date(), reason: status)
        statusMessage = "\(status) with \(selected.count) profiles..."
        sendGoogleChatMessage(.started(job: job, destinations: uniqueDestinations(for: selected.map(\.name))))

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
                flushCompletedFileNotifications(force: true)
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
                sendGoogleChatMessage(.finished(job: job, status: finalStatus, runSummaries: finalRuns.map { "\(destinationSummary(for: $0.remoteName)): \($0.state.label), \(TransferStatsParser.formatBytes($0.transferredBytes))" }))
                if completed {
                    cleanupTemporaryUploadFolderIfNeeded(for: job)
                }
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
        statusMessage = "Transfer paused. Keep GDriveVault open to resume the active partial file."
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
        collectRemoteChanges(from: chunk, remoteName: remoteName)
        collectCompletedFiles(from: chunk, remoteName: remoteName)
        if let progress = TransferStatsParser.progress(in: chunk) {
            runs[index].progress = progress
            sendGoogleChatProgress(progress, remoteName: remoteName)
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

    private func resetRemoteChangeTracking() {
        recentRemoteChanges = []
        changeKeys = []
        filesAdded = 0
        filesUpdated = 0
        filesDeleted = 0
        bytesAdded = 0
        bytesUpdated = 0
    }

    private func collectRemoteChanges(from chunk: String, remoteName: String) {
        for change in Self.remoteChanges(in: chunk, remoteName: remoteName) {
            let key = "\(change.action)|\(change.remoteName)|\(change.path)"
            guard !changeKeys.contains(key) else { continue }
            changeKeys.insert(key)

            switch change.action {
            case "added":
                filesAdded += 1
                bytesAdded += change.bytes ?? 0
            case "updated":
                filesUpdated += 1
                bytesUpdated += change.bytes ?? 0
            case "deleted":
                filesDeleted += 1
            default:
                break
            }

            recentRemoteChanges.insert(change, at: 0)
            if recentRemoteChanges.count > 30 {
                recentRemoteChanges.removeLast(recentRemoteChanges.count - 30)
            }
        }
    }

    private static func remoteChanges(in text: String, remoteName: String) -> [RemoteControlChange] {
        text
            .split(separator: "\n")
            .compactMap { line -> RemoteControlChange? in
                let value = normalizedRcloneLogMessage(String(line))
                guard !value.isEmpty else { return nil }

                let lowercased = value.lowercased()
                let action: String
                if lowercased.contains(": copied") || lowercased.contains(": transferred") {
                    action = lowercased.contains("replaced") || lowercased.contains("updated") ? "updated" : "added"
                } else if lowercased.contains(": deleted") || lowercased.contains(": removed") {
                    action = "deleted"
                } else if lowercased.contains(": updated") || lowercased.contains(": replaced") {
                    action = "updated"
                } else {
                    return nil
                }

                let path = Self.pathBeforeFirstColon(in: value)
                guard !path.isEmpty,
                      !path.localizedCaseInsensitiveContains("transferred"),
                      !path.localizedCaseInsensitiveContains("checks")
                else { return nil }

                return RemoteControlChange(
                    action: action,
                    path: path,
                    bytes: Self.bytesMentioned(in: value),
                    remoteName: remoteName,
                    timestamp: Date()
                )
            }
    }

    private static func pathBeforeFirstColon(in value: String) -> String {
        guard let colon = value.firstIndex(of: ":") else { return "" }
        return String(value[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedRcloneLogMessage(_ line: String) -> String {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: #"(?i)\b(?:INFO|NOTICE|ERROR|DEBUG|WARNING)\s+:\s*"#, options: .regularExpression) {
            return String(value[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func bytesMentioned(in value: String) -> Int64? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?i?B|[KMGTPE]?B|[KMGTPE])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let number = Double(value[valueRange])
        else { return nil }

        return Int64(number * bytesMultiplier(for: String(value[unitRange])))
    }

    private static func bytesMultiplier(for unit: String) -> Double {
        switch unit.lowercased() {
        case "k", "kb":
            1_000
        case "ki", "kib":
            1_024
        case "m", "mb":
            1_000_000
        case "mi", "mib":
            1_048_576
        case "g", "gb":
            1_000_000_000
        case "gi", "gib":
            1_073_741_824
        case "t", "tb":
            1_000_000_000_000
        case "ti", "tib":
            1_099_511_627_776
        default:
            1
        }
    }

    private func collectCompletedFiles(from chunk: String, remoteName: String) {
        guard googleChatSettings.isConfigured, googleChatSettings.notifyCompletedFiles else { return }

        let files = Self.completedFileNames(in: chunk)
        guard !files.isEmpty else { return }

        var buffer = completedFileBufferByRemote[remoteName, default: []]
        files.forEach { buffer.insert($0) }
        completedFileBufferByRemote[remoteName] = buffer
        flushCompletedFileNotifications(force: buffer.count >= max(1, googleChatSettings.fileBatchSize))
    }

    private func flushCompletedFileNotifications(force: Bool) {
        guard force, googleChatSettings.isConfigured, googleChatSettings.notifyCompletedFiles else { return }

        let buffers = completedFileBufferByRemote
        completedFileBufferByRemote = [:]

        for (remoteName, files) in buffers where !files.isEmpty {
            let sortedFiles = files.sorted()
            let visibleFiles = sortedFiles.prefix(12).map { "• \($0)" }.joined(separator: "\n")
            let extraCount = sortedFiles.count - min(sortedFiles.count, 12)
            let extraText = extraCount > 0 ? "\n…and \(extraCount) more file\(extraCount == 1 ? "" : "s")." : ""
            sendGoogleChatText("""
            GDriveVault completed \(sortedFiles.count) file\(sortedFiles.count == 1 ? "" : "s")
            Destination: \(destinationSummary(for: remoteName))
            \(visibleFiles)\(extraText)
            """)
        }
    }

    private func sendGoogleChatProgress(_ progress: TransferProgress, remoteName: String) {
        guard googleChatSettings.isConfigured else { return }

        let now = Date()
        let percent = progress.percent ?? Int(progress.fractionComplete * 100)
        let previousPercent = lastChatProgressPercentByRemote[remoteName] ?? -10
        let previousDate = lastChatProgressSentAtByRemote[remoteName] ?? .distantPast
        let enoughPercentChange = percent >= previousPercent + 10
        let enoughTimeElapsed = now.timeIntervalSince(previousDate) >= 60
        guard enoughPercentChange || enoughTimeElapsed else { return }

        lastChatProgressSentAtByRemote[remoteName] = now
        lastChatProgressPercentByRemote[remoteName] = percent

        let totalText = progress.totalBytes.map { " / \(TransferStatsParser.formatBytes($0))" } ?? ""
        let fileText = progress.activeFiles.prefix(5).map { file in
            let filePercent = file.percent.map { " \($0)%" } ?? ""
            return "• \(file.name)\(filePercent)"
        }
        .joined(separator: "\n")

        sendGoogleChatText("""
        GDriveVault progress: \(job.name)
        Destination: \(destinationSummary(for: remoteName))
        Progress: \(percent)% · \(TransferStatsParser.formatBytes(progress.transferredBytes))\(totalText)
        Speed: \(TransferStatsParser.formatSpeed(progress.speedBytesPerSecond))
        ETA: \(progress.eta ?? "-")
        Active file\(progress.activeFiles.count == 1 ? "" : "s"):
        \(fileText.isEmpty ? "• Waiting for file detail from rclone" : fileText)
        """)
    }

    private func sendGoogleChatMessage(_ event: GoogleChatEvent) {
        let settings = googleChatSettings
        guard settings.isConfigured else { return }

        switch event {
        case .started where !settings.notifyStarted:
            return
        case .finished(_, let status, _) where status == "Sync completed." && !settings.notifyCompleted:
            return
        case .finished where !settings.notifyFailed:
            return
        default:
            break
        }

        sendGoogleChatText(event.message)
    }

    private func sendGoogleChatText(_ text: String) {
        let settings = googleChatSettings
        Task {
            do {
                try await googleChat.send(text, settings: settings)
            } catch {
                await MainActor.run {
                    statusMessage = "Google Chat notification failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private static func completedFileNames(in text: String) -> [String] {
        text
            .split(separator: "\n")
            .compactMap { line -> String? in
                let value = normalizedRcloneLogMessage(String(line))
                guard value.localizedCaseInsensitiveContains("copied") else { return nil }
                if let colon = value.firstIndex(of: ":") {
                    let candidate = String(value[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return candidate.isEmpty ? nil : candidate
                }
                return value
            }
    }

    private func destinationSummary(for remoteName: String) -> String {
        _ = remoteName
        return teamDestinationPath()
    }

    private func uniqueDestinations(for remoteNames: [String]) -> [String] {
        var seen = Set<String>()
        return remoteNames.compactMap { remoteName in
            let destination = destinationSummary(for: remoteName)
            return seen.insert(destination).inserted ? destination : nil
        }
    }

    private func teamDestinationPath() -> String {
        let rootName = job.remoteRootName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = rootName?.isEmpty == false ? rootName! : "MrHandPay"
        let cleanedPath = job.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return cleanedPath.isEmpty ? root : "\(root)/\(cleanedPath)"
    }

    private func startRemoteControlLoopIfNeeded() {
        remoteControlTask?.cancel()
        remoteControlTask = nil

        guard remoteControlSettings.isRegistered else { return }

        remoteControlTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let settings = await MainActor.run { self.remoteControlSettings }
                guard settings.isRegistered else { return }

                do {
                    let heartbeat = await MainActor.run { self.makeRemoteControlHeartbeat() }
                    try await self.remoteControlService.sendHeartbeat(heartbeat, settings: settings)

                    let commands = try await self.remoteControlService.fetchCommands(settings: settings)
                    for command in commands {
                        try await self.handleRemoteControlCommand(command, settings: settings)
                        try await self.remoteControlService.acknowledge(commandID: command.id, settings: settings)
                    }

                    await MainActor.run {
                        self.remoteControlStatus = commands.isEmpty ? "Connected. Waiting for commands." : "Processed \(commands.count) command\(commands.count == 1 ? "" : "s")."
                        self.uploadSettingsBackupAfterControlConnectionIfNeeded()
                    }
                } catch {
                    await MainActor.run {
                        if self.isRemoteLicenseFailure(error) {
                            self.lockApplicationForLicenseFailure(message: error.localizedDescription)
                        } else {
                            self.remoteControlStatus = "Remote control error: \(error.localizedDescription)"
                        }
                    }
                }

                let seconds = max(2, settings.pollIntervalSeconds)
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            }
        }
    }

    private func uploadSettingsBackupAfterControlConnectionIfNeeded() {
        guard !didUploadSettingsBackupForCurrentConnection,
              !isUploadingSettingsBackup,
              remoteControlSettings.isRegistered
        else { return }

        uploadSettingsBackupToControlServer(automatic: true)
    }

    private func isRemoteLicenseFailure(_ error: Error) -> Bool {
        guard case RemoteControlService.RemoteControlError.httpStatus(let status, let message) = error else {
            return false
        }
        if status == 403 { return true }
        if status == 401 {
            let text = (message ?? "").lowercased()
            return text.contains("license") || text.contains("token") || text.contains("bearer")
        }
        return false
    }

    private func lockApplicationForLicenseFailure(message: String) {
        remoteControlTask?.cancel()
        remoteControlTask = nil
        pendingRegistrationTask?.cancel()
        pendingRegistrationTask = nil

        remoteControlSettings.deviceID = nil
        remoteControlSettings.token = nil
        remoteControlSettings.licenseKey = ""
        remoteControlSettings.approvalRequestID = nil
        remoteControlSettings.isEnabled = true
        isLicenseLocked = true
        didUploadSettingsBackupForCurrentConnection = false
        remoteControlStatus = "License required. Register this app to continue."
        statusMessage = "GDriveVault is disabled until a valid license key is registered."
        isRemoteControlSettingsPresented = true

        let settings = remoteControlSettings
        Task {
            await remoteControlSettingsStore.save(settings)
        }
        autoRegisterRemoteControlIfNeeded(reason: "license required")
    }

    private func ensureLicenseAllowsOperation() -> Bool {
        guard !requiresRegistration else {
            statusMessage = "GDriveVault is disabled until this Mac is registered with a valid license key."
            isRemoteControlSettingsPresented = true
            return false
        }
        return true
    }

    private func makeRemoteControlHeartbeat() -> RemoteControlHeartbeat {
        let activeRun = runs.last { run in
            if case .running = run.state {
                return true
            }
            return false
        }
        let usage = Dictionary(uniqueKeysWithValues: accountUsages.map { ($0.remoteName, $0.bytesTransferred) })

        return RemoteControlHeartbeat(
            status: isPaused ? "paused" : (isRunning ? "running" : "idle"),
            jobName: isRunning || hasRunnableJob ? job.name : nil,
            remoteName: activeRun?.remoteName,
            transferredBytes: activeRun?.progress?.transferredBytes ?? activeRun?.transferredBytes ?? runs.reduce(Int64(0)) { $0 + $1.transferredBytes },
            speedBps: activeRun?.progress?.speedBytesPerSecond,
            eta: activeRun?.progress?.eta,
            accountUsage: usage,
            appVersion: AppVersion.current,
            hostname: Host.current().localizedName,
            platform: "macOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: ProcessInfo.processInfo.machineHardwareName,
            syncRoot: job.localPath,
            currentFile: activeRun?.progress?.activeFiles.first?.name,
            filesCompleted: activeRun?.progress?.filesDone,
            filesTotal: activeRun?.progress?.filesTotal,
            filesAdded: filesAdded,
            filesUpdated: filesUpdated,
            filesDeleted: filesDeleted,
            bytesAdded: bytesAdded,
            bytesUpdated: bytesUpdated,
            recentChanges: Array(recentRemoteChanges.prefix(12)),
            internetDownloadMbps: latestBandwidthTest?.downloadMbps,
            internetUploadMbps: latestBandwidthTest?.uploadMbps,
            internetPublicIP: latestBandwidthTest?.publicIP,
            internetLocation: latestBandwidthTest?.location,
            internetProvider: latestBandwidthTest?.provider,
            speedTestedAt: latestBandwidthTest?.testedAt,
            error: latestRunError()
        )
    }

    private func latestRunError() -> String? {
        for run in runs.reversed() {
            switch run.state {
            case .failed(let message), .skipped(let message):
                return message
            case .finished(let code) where code != 0:
                return "rclone exited \(code)"
            case .idle, .running, .cancelled, .finished:
                continue
            }
        }
        return nil
    }

    private func handleRemoteControlCommand(_ command: RemoteControlCommand, settings: RemoteControlSettings) async throws {
        switch command.command {
        case "start", "start_current":
            await MainActor.run { start() }
        case "start_job":
            await MainActor.run { startRemoteJob(payload: command.payload ?? [:]) }
        case "stop", "pause":
            await MainActor.run { stop() }
        case "resume":
            await MainActor.run {
                if isRunning && isPaused {
                    continuePausedRun()
                } else {
                    resume()
                }
            }
        case "cancel", "cancel_job":
            await MainActor.run { cancelJob() }
        case "refresh_remotes":
            await MainActor.run { refreshRemotes() }
        case "check_updates":
            await MainActor.run { checkForUpdates(showUpToDate: true) }
        case "install_update", "force_update":
            try await installLatestUpdateFromControl(payload: command.payload ?? [:])
        case "restart", "restart_app":
            await MainActor.run { restartApplicationFromRemoteCommand() }
        case "restore_settings_backup":
            guard let backupID = command.payload?["backup_id"] ?? command.payload?["backupID"] else {
                throw RestoreSettingsError.missingBackupID
            }
            try await restoreSettingsBackupFromControlServer(backupID: backupID, settings: settings)
        default:
            await MainActor.run {
                statusMessage = "Unknown remote command: \(command.command)"
            }
        }
    }

    private func restartApplicationFromRemoteCommand() {
        guard !isRunning else {
            statusMessage = "Remote restart ignored while a transfer is running."
            return
        }

        statusMessage = "Remote restart requested. Relaunching GDriveVault..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.relaunchApplication()
            NSApp.terminate(nil)
        }
    }

    private func relaunchApplication() {
        let process = Process()
        if Bundle.main.bundleURL.pathExtension == "app" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", Bundle.main.bundleURL.path]
        } else if let executableURL = Bundle.main.executableURL {
            process.executableURL = executableURL
            process.arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
        }
        try? process.run()
    }

    private func startRemoteJob(payload: [String: String]) {
        guard !isRunning else { return }

        if let id = payload["job_id"],
           let uuid = UUID(uuidString: id),
           let savedJob = savedJobs.first(where: { $0.id == uuid }) {
            runJob(savedJob)
            return
        }

        if let name = payload["job_name"] ?? payload["name"],
           let savedJob = savedJobs.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            runJob(savedJob)
            return
        }

        statusMessage = "Remote command could not find the requested sync job."
    }

    private func dropUploadBaseJob() -> SyncJob? {
        if hasRunnableJob {
            return job
        }
        if savedJobs.count == 1 {
            return savedJobs.first
        }
        return nil
    }

    private func uniquedDroppedItems(_ items: [DroppedUploadItem]) -> [DroppedUploadItem] {
        var seen = Set<String>()
        return items.filter { item in
            seen.insert(item.path).inserted
        }
    }

    private func prepareDroppedUploadJob(baseJob: SyncJob, items: [DroppedUploadItem], shouldStage: Bool) throws -> SyncJob {
        var uploadJob = baseJob
        uploadJob.id = UUID()
        uploadJob.mode = .copy
        uploadJob.direction = .upload
        uploadJob.name = "Dropped upload"
        uploadJob.dryRun = false
        uploadJob.cleanupLocalPathAfterRun = nil

        if shouldStage {
            let stageURL = try createStagedUploadFolder(for: items)
            uploadJob.localPath = stageURL.path
            uploadJob.remotePath = baseJob.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            uploadJob.cleanupLocalPathAfterRun = stageURL.path
            return uploadJob
        }

        guard let item = items.first else { return uploadJob }
        uploadJob.localPath = item.path
        if item.isDirectory {
            uploadJob.remotePath = joinedRemotePath(baseJob.remotePath, item.name)
        } else {
            uploadJob.remotePath = baseJob.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return uploadJob
    }

    private func createStagedUploadFolder(for items: [DroppedUploadItem]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GDriveVault Drop Uploads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for item in items {
            let destination = uniqueDestinationURL(for: item.name, in: root)
            try FileManager.default.copyItem(at: item.url, to: destination)
        }

        return root
    }

    private func uniqueDestinationURL(for name: String, in folder: URL) -> URL {
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: name).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var index = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            let fileName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = folder.appendingPathComponent(fileName)
            index += 1
        }

        return candidate
    }

    private func joinedRemotePath(_ base: String, _ child: String) -> String {
        let cleanedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanedChild = child.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanedBase.isEmpty else { return cleanedChild }
        guard !cleanedChild.isEmpty else { return cleanedBase }
        return "\(cleanedBase)/\(cleanedChild)"
    }

    private func cleanupTemporaryUploadFolderIfNeeded(for completedJob: SyncJob) {
        guard let path = completedJob.cleanupLocalPathAfterRun else { return }
        Task.detached {
            try? FileManager.default.removeItem(atPath: path)
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
