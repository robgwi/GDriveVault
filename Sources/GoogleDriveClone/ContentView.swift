import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers

private final class DroppedURLCollector: @unchecked Sendable {
    private var urls: [URL] = []
    private let lock = NSLock()

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        let result = urls
        lock.unlock()
        return result
    }
}

private enum AppPage: String, CaseIterable, Identifiable {
    case dashboard
    case syncSettings
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .syncSettings: "Sync Profiles"
        case .status: "Status"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "rectangle.grid.2x2"
        case .syncSettings: "slider.horizontal.3"
        case .status: "waveform.path.ecg"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Quick upload and live transfer health"
        case .syncSettings: "Saved sync profiles and job setup"
        case .status: "Run logs and failover history"
        }
    }
}

private enum ControlConnectionState {
    case connected
    case connecting
    case disabled
    case error
}

struct ContentView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @AppStorage("gdrivevault.welcomeShown.v1") private var isWelcomeShown = false
    @AppStorage("gdrivevault.fullDiskAccessSetupComplete.v1") private var isFullDiskAccessSetupComplete = false
    @State private var selectedPage: AppPage = .dashboard
    @State private var isSettingsPresented = false
    @State private var isWelcomePresented = false
    @State private var isFullDiskAccessGuidePresented = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                ScrollView {
                    pageContent
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color.blue.opacity(0.045),
                            Color.green.opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("GDriveVault")
        .task {
            if coordinator.remotes.isEmpty {
                coordinator.refreshRemotes()
            }
            coordinator.checkForUpdates(showUpToDate: false)
            presentWelcomeOrFullDiskAccessGuideIfNeeded()
        }
        .onChange(of: coordinator.remoteControlSettings.isRegistered) {
            presentWelcomeOrFullDiskAccessGuideIfNeeded()
        }
        .alert(item: $coordinator.updateNotification) { notification in
            if let actionTitle = notification.actionTitle {
                Alert(
                    title: Text(notification.title),
                    message: Text(notification.message),
                    primaryButton: .default(Text(actionTitle)) {
                        coordinator.installUpdateFromNotification(notification)
                    },
                    secondaryButton: .cancel()
                )
            } else {
                Alert(
                    title: Text(notification.title),
                    message: Text(notification.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .sheet(isPresented: $coordinator.isProfileEditorPresented) {
            ProfileEditorView()
                .environmentObject(coordinator)
                .frame(minWidth: 820, minHeight: 620)
        }
        .sheet(isPresented: $coordinator.isRemoteBrowserPresented) {
            RemoteBrowserView()
                .environmentObject(coordinator)
                .frame(minWidth: 760, minHeight: 560)
        }
        .sheet(isPresented: $coordinator.isDownloadBrowserPresented) {
            RemoteDownloadBrowserView()
                .environmentObject(coordinator)
                .frame(minWidth: 860, minHeight: 620)
        }
        .sheet(isPresented: $coordinator.isDownloadManagerPresented) {
            DownloadTransferWindow()
                .environmentObject(coordinator)
                .frame(minWidth: 820, minHeight: 620)
        }
        .sheet(isPresented: $coordinator.isChatSettingsPresented) {
            GoogleChatSettingsView()
                .environmentObject(coordinator)
                .frame(minWidth: 680, minHeight: 520)
        }
        .sheet(isPresented: $coordinator.isRemoteControlSettingsPresented) {
            RemoteControlSettingsView()
                .environmentObject(coordinator)
                .frame(minWidth: 680, minHeight: 540)
        }
        .sheet(isPresented: $isSettingsPresented) {
            AppSettingsView(
                selectedPage: $selectedPage,
                isPresented: $isSettingsPresented,
                onOpenFullDiskAccessGuide: {
                    isSettingsPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isFullDiskAccessGuidePresented = true
                    }
                }
            )
                .environmentObject(coordinator)
                .frame(minWidth: 760, minHeight: 560)
        }
        .sheet(isPresented: $isFullDiskAccessGuidePresented) {
            FullDiskAccessGuideView(isSetupComplete: $isFullDiskAccessSetupComplete)
                .frame(minWidth: 680, minHeight: 520)
        }
        .sheet(isPresented: $isWelcomePresented, onDismiss: {
            presentFullDiskAccessGuideIfNeeded()
        }) {
            WelcomeView(isWelcomeShown: $isWelcomeShown)
                .frame(minWidth: 760, minHeight: 640)
        }
    }

    private func presentWelcomeOrFullDiskAccessGuideIfNeeded() {
        guard !coordinator.requiresRegistration,
              !coordinator.isRemoteControlSettingsPresented else { return }
        if !isWelcomeShown {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard !isWelcomeShown,
                      !coordinator.requiresRegistration,
                      !coordinator.isRemoteControlSettingsPresented else { return }
                isWelcomePresented = true
            }
        } else {
            presentFullDiskAccessGuideIfNeeded()
        }
    }

    private func presentFullDiskAccessGuideIfNeeded() {
        guard !isFullDiskAccessSetupComplete,
              isWelcomeShown,
              !coordinator.requiresRegistration,
              !coordinator.isRemoteControlSettingsPresented else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard !isFullDiskAccessSetupComplete,
                  isWelcomeShown,
                  !coordinator.requiresRegistration,
                  !coordinator.isRemoteControlSettingsPresented else { return }
            isFullDiskAccessGuidePresented = true
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "cloud.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("GDriveVault")
                        .font(.headline)
                    Text("for Google")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            if coordinator.organizationBranding.isConfigured {
                HStack(spacing: 10) {
                    BrandingLogoView(path: coordinator.organizationBranding.logoPath, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(coordinator.organizationBranding.displayName)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(coordinator.organizationBranding.managedStatement)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(AppPage.allCases) { page in
                    Button {
                        selectedPage = page
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.icon)
                                .font(.title3)
                                .foregroundStyle(selectedPage == page ? .blue : .secondary)
                                .frame(width: 34, height: 34)
                                .background((selectedPage == page ? Color.blue : Color.primary).opacity(selectedPage == page ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(page.title)
                                    .font(.callout.weight(.medium))
                                Text(page.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(selectedPage == page ? Color.blue.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Sync Pool", systemImage: "person.2.wave.2")
                        .font(.headline)
                    Spacer()
                    Button {
                        coordinator.refreshRemotes()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh remotes")
                    .disabled(coordinator.isRefreshing)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(coordinator.job.selectedRemoteNames.count) of \(coordinator.remotes.count) profiles selected")
                        .font(.callout.weight(.medium))
                    Text("Choose accounts in Sync Profiles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    selectedPage = .syncSettings
                } label: {
                    Label("Set Profiles", systemImage: "checklist")
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.remotes.isEmpty)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            Divider()

            HStack(spacing: 10) {
                SidebarMetric(icon: "person.2", value: "\(coordinator.remotes.count)", title: "Profiles")
                SidebarMetric(icon: "checkmark.circle", value: "\(coordinator.job.selectedRemoteNames.count)", title: "Selected")
            }

            SidebarMetric(icon: "tray.full", value: "\(coordinator.savedJobs.count)", title: "Saved Jobs")

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                Label("Status", systemImage: coordinator.isRunning ? "bolt.horizontal.circle.fill" : "circle.dotted")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(coordinator.isRunning ? .green : .secondary)
                Text(coordinator.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if coordinator.isRunning {
                    ProgressView(value: liveTransferFraction)
                        .tint(.green)
                    Text("\(liveTransferredText) • \(TransferStatsParser.formatSpeed(activeRun?.progress?.speedBytesPerSecond)) • ETA \(activeRun?.progress?.eta ?? "-")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("\(coordinator.remotes.count) profiles loaded")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            Button {
                isSettingsPresented = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color.blue.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedPage.title)
                    .font(.title2.weight(.semibold))
                Text(selectedPage.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                coordinator.openRemoteControlSettings()
            } label: {
                Label(controlConnectionLabel, systemImage: controlConnectionIcon)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(controlConnectionTint)
            .help("\(controlConnectionLabel): \(coordinator.remoteControlStatus)")

            Button {
                isSettingsPresented = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .controlSize(.large)

            Button {
                coordinator.checkForUpdates(showUpToDate: true)
            } label: {
                Label("Updates", systemImage: "arrow.down.circle")
            }
            .controlSize(.large)
            .disabled(coordinator.isCheckingForUpdates)

            if coordinator.isRunning {
                if coordinator.isPaused {
                    Button {
                        coordinator.continuePausedRun()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        coordinator.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button(role: .destructive) {
                    coordinator.cancelJob()
                } label: {
                    Label("Cancel Job", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                if coordinator.canResume {
                    Button {
                        coordinator.resume()
                    } label: {
                        Label("Restart Sync", systemImage: "playpause.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Button {
                    handleToolbarStart()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(coordinator.requiresRegistration || coordinator.isRunningBandwidthTest || (coordinator.savedJobs.isEmpty && !coordinator.hasRunnableJob))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func handleToolbarStart() {
        if coordinator.hasRunnableJob {
            coordinator.start()
            return
        }

        if coordinator.savedJobs.count == 1, let onlyJob = coordinator.savedJobs.first {
            coordinator.runJob(onlyJob)
            return
        }

        selectedPage = .syncSettings
        if coordinator.savedJobs.isEmpty {
            coordinator.statusMessage = "Create and save a sync profile before starting."
        } else {
            coordinator.statusMessage = "Choose a sync profile to run."
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .dashboard:
            VStack(alignment: .leading, spacing: 20) {
                hero
                dropUploadPanel
                quickDownloadPanel
                quickStats
                liveTransferPanel
            }
        case .syncSettings:
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(
                    title: "Sync Profiles",
                    subtitle: "Select a saved sync profile or create a new one before editing job details.",
                    icon: "slider.horizontal.3"
                )
                jobLibrary
                if coordinator.hasActiveJob {
                    jobEditor
                } else {
                    noJobSelected
                }
            }
        case .status:
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(
                    title: "Status",
                    subtitle: "Watch failover progress, per-account caps, and rclone output.",
                    icon: "waveform.path.ecg"
                )
                runList
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .leading) {
            Image("gdrivevault-hero", bundle: .gdriveVaultResources)
                .resizable()
                .scaledToFill()
                .frame(height: 220)
                .clipped()

            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.94),
                    Color(nsColor: .windowBackgroundColor).opacity(0.60),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "cloud.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("GDriveVault")
                        .font(.largeTitle.weight(.semibold))
                }

                Text("Welcome to GDriveVault--a faster, more powerful way to manage your Google Drive files on macOS.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 500, alignment: .leading)

                HStack(spacing: 12) {
                    Label("\(coordinator.remotes.count) profiles", systemImage: "person.2.wave.2")
                    Label(coordinator.job.dryRun ? "Dry run armed" : "Live sync armed", systemImage: coordinator.job.dryRun ? "eye" : "bolt.fill")
                }
                .font(.callout.weight(.medium))
            }
            .padding(26)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08))
        }
    }

    private var quickStats: some View {
        HStack(spacing: 14) {
            StatTile(title: "Profiles", value: "\(coordinator.remotes.count)", icon: "person.2.wave.2", tint: .blue)
            StatTile(title: "Selected", value: "\(coordinator.job.selectedRemoteNames.count)", icon: "checkmark.circle", tint: .green)
            StatTile(title: "Pool Left", value: TransferStatsParser.formatBytes(selectedRemainingBytes), icon: "gauge.with.dots.needle.67percent", tint: .cyan)
            StatTile(title: "Internet", value: bandwidthSpeedText, icon: "network", tint: .purple)
            StatTile(title: "Live", value: liveTransferredText, icon: coordinator.isRunning ? "arrow.up.forward.circle.fill" : "pause.circle", tint: coordinator.isRunning ? .green : .orange)
            StatTile(title: "Control", value: controlConnectionShortLabel, icon: controlConnectionIcon, tint: controlConnectionTint)
        }
    }

    private var controlConnectionLabel: String {
        switch controlConnectionState {
        case .connected: "Control connected"
        case .connecting: "Control connecting"
        case .disabled: "Control off"
        case .error: "Control error"
        }
    }

    private var controlConnectionShortLabel: String {
        switch controlConnectionState {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disabled: "Off"
        case .error: "Error"
        }
    }

    private var controlConnectionIcon: String {
        switch controlConnectionState {
        case .connected: "checkmark.icloud.fill"
        case .connecting: "arrow.triangle.2.circlepath.icloud"
        case .disabled: "icloud.slash"
        case .error: "exclamationmark.icloud.fill"
        }
    }

    private var controlConnectionTint: Color {
        switch controlConnectionState {
        case .connected: .green
        case .connecting: .blue
        case .disabled: .secondary
        case .error: .red
        }
    }

    private var controlConnectionState: ControlConnectionState {
        if coordinator.isRegisteringRemoteControl || coordinator.isTestingRemoteControl {
            return .connecting
        }
        if coordinator.isLicenseLocked {
            return .error
        }
        let status = coordinator.remoteControlStatus.lowercased()
        if status.contains("error") || status.contains("failed") || status.contains("invalid") || status.contains("rejected") {
            return .error
        }
        if coordinator.remoteControlSettings.isRegistered,
           status.contains("connected") || status.contains("ready") || status.contains("waiting") || status.contains("processed") || status.contains("registered") {
            return .connected
        }
        return .connecting
    }

    private var dropUploadPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Quick Upload", systemImage: "tray.and.arrow.up.fill")
                    .font(.headline)
                Spacer()
                Text(dropUploadDestinationText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Drop files or folders here")
                    .font(.title3.weight(.semibold))
                Text("GDriveVault will upload them to \(dropUploadDestinationText). Multiple dropped items are staged into a temporary batch and removed after the run.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .padding(18)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    .foregroundStyle(Color.blue.opacity(0.36))
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDroppedProviders(providers)
            }

            if !coordinator.droppedUploadItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(coordinator.droppedUploadItems) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(item.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Toggle("Stage files before upload", isOn: $coordinator.stageDroppedUploads)
                    .toggleStyle(.checkbox)
                    .disabled(coordinator.droppedUploadItems.count > 1)
                Text(coordinator.droppedUploadItems.count > 1 ? "Required for multiple dropped items." : "Safer for long uploads if the source may move.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    coordinator.clearDroppedUploads()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(coordinator.droppedUploadItems.isEmpty || coordinator.isRunning || coordinator.isPreparingDroppedUpload)

                Button {
                    coordinator.uploadDroppedItems()
                } label: {
                    if coordinator.isPreparingDroppedUpload {
                        Label("Preparing", systemImage: "hourglass")
                    } else {
                        Label("Upload", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.requiresRegistration || coordinator.droppedUploadItems.isEmpty || coordinator.isRunning || coordinator.isRunningBandwidthTest || coordinator.isPreparingDroppedUpload)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07))
        }
    }

    private var quickDownloadPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Quick Download", systemImage: "arrow.down.folder.fill")
                    .font(.headline)
                Spacer()
                Text(downloadDestinationSummary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 18) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 58, height: 58)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Browse Google Drive and download files")
                        .font(.title3.weight(.semibold))
                    Text("Select files or folders from the remote drive, choose a local destination, then watch progress with pause, resume, and cancel controls.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    coordinator.openDownloadBrowser()
                } label: {
                    Label("Browse Drive", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(coordinator.requiresRegistration || coordinator.remotes.isEmpty || coordinator.isRunning)
            }

            HStack(spacing: 16) {
                LiveMetric(title: "Profiles", value: "\(coordinator.job.selectedRemoteNames.count)", icon: "person.2")
                LiveMetric(title: "Destination", value: coordinator.downloadLocalPath, icon: "folder")
                LiveMetric(title: "Status", value: downloadStatusText, icon: coordinator.isRunning && coordinator.job.direction == .download ? "arrow.down.circle.fill" : "circle")
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07))
        }
    }

    private var bandwidthPanel: some View {
        ConnectionCheckPanel()
    }

    private var liveTransferPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Live Transfer", systemImage: coordinator.isRunning ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                    .font(.headline)
                    .foregroundStyle(coordinator.isRunning ? .green : .primary)
                Spacer()
                Text(activeRun?.remoteName.trimmingCharacters(in: CharacterSet(charactersIn: ":")) ?? "Idle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: liveTransferFraction)
                .tint(coordinator.isRunning ? .green : .blue)

            HStack(spacing: 16) {
                LiveMetric(title: "Transferred", value: liveTransferredText, icon: "arrow.up.doc")
                LiveMetric(title: "Current cap", value: liveCapText, icon: "speedometer")
                LiveMetric(title: "Active account", value: activeRun?.remoteName.trimmingCharacters(in: CharacterSet(charactersIn: ":")) ?? "None", icon: "person.crop.circle")
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07))
        }
    }

    private var accountTracker: some View {
        AccountTrackerPanel()
    }

    private var selectedRemainingBytes: Int64 {
        coordinator.job.selectedRemoteNames.reduce(Int64(0)) { total, remoteName in
            total + coordinator.usage(for: remoteName).remainingBytes
        }
    }

    private var dropUploadDestinationText: String {
        let baseJob = coordinator.hasRunnableJob ? coordinator.job : (coordinator.savedJobs.count == 1 ? coordinator.savedJobs[0] : coordinator.job)
        let rootName = baseJob.remoteRootName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = rootName?.isEmpty == false ? rootName! : "MrHandPay"
        let path = baseJob.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? root : "\(root)/\(path)"
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        let collector = DroppedURLCollector()
        let group = DispatchGroup()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let droppedURL: URL?
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    droppedURL = url
                } else if let url = item as? URL {
                    droppedURL = url
                } else {
                    droppedURL = nil
                }

                if let droppedURL {
                    collector.append(droppedURL)
                }
            }
        }

        group.notify(queue: .main) {
            coordinator.addDroppedUploadURLs(collector.snapshot())
        }

        return true
    }

    private var activeRun: SyncRun? {
        coordinator.runs.last(where: { run in
            if case .running = run.state {
                return true
            }
            return false
        })
    }

    private var liveTransferredText: String {
        TransferStatsParser.formatBytes(activeRun?.progress?.transferredBytes ?? activeRun?.transferredBytes ?? coordinator.runs.reduce(Int64(0)) { $0 + $1.transferredBytes })
    }

    private var downloadDestinationSummary: String {
        coordinator.downloadLocalPath.isEmpty ? "Choose a local destination" : coordinator.downloadLocalPath
    }

    private var downloadStatusText: String {
        if coordinator.isRunning, coordinator.job.direction == .download {
            return coordinator.isPaused ? "Paused" : "Downloading"
        }
        if coordinator.canResume, coordinator.job.direction == .download {
            return "Resume available"
        }
        return "Ready"
    }

    private var bandwidthSpeedText: String {
        if coordinator.isRunningBandwidthTest {
            return "Testing"
        }
        return coordinator.latestBandwidthTest?.displaySpeed ?? "No test"
    }

    private var bandwidthSampleText: String {
        guard let result = coordinator.latestBandwidthTest else { return "-" }
        return TransferStatsParser.formatBytes(result.bytesDownloaded)
    }

    private var liveCapText: String {
        if let totalBytes = activeRun?.progress?.totalBytes {
            return TransferStatsParser.formatBytes(totalBytes)
        }
        guard let maxTransferBytes = activeRun?.maxTransferBytes else {
            return coordinator.isRunning ? "Dry run" : "No active cap"
        }
        return TransferStatsParser.formatBytes(maxTransferBytes)
    }

    private var liveTransferFraction: Double {
        if let progress = activeRun?.progress {
            return progress.fractionComplete
        }
        guard let activeRun, let cap = activeRun.maxTransferBytes, cap > 0 else {
            return coordinator.isRunning ? 0.08 : 0
        }
        return min(1, Double(activeRun.transferredBytes) / Double(cap))
    }

    private var jobLibrary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Saved Sync Profiles", systemImage: "tray.full")
                    .font(.headline)
                Spacer()
                Button {
                    coordinator.newJob()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .disabled(coordinator.isRunning)
            }

            if coordinator.savedJobs.isEmpty {
                ContentUnavailableView("No saved sync profiles", systemImage: "tray", description: Text("Click New to configure and save a reusable sync profile."))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 8) {
                    ForEach(coordinator.savedJobs) { savedJob in
                        SavedJobRow(
                            job: savedJob,
                            isSelected: coordinator.selectedJobID == savedJob.id,
                            isRunning: coordinator.runningJobID == savedJob.id,
                            isPaused: coordinator.isPaused,
                            isAnyRunning: coordinator.isRunning,
                            onEdit: {
                                coordinator.selectJob(savedJob)
                            },
                            onRun: {
                                coordinator.runJob(savedJob)
                            },
                            onPause: {
                                coordinator.stop()
                            },
                            onResume: {
                                coordinator.continuePausedRun()
                            },
                            onStop: {
                                coordinator.cancelJob()
                            }
                        )
                    }
                }
            }

            HStack {
                Text(coordinator.hasActiveJob ? "Current draft: \(coordinator.job.name)" : "Select a sync profile or click New")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    coordinator.duplicateCurrentJob()
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .disabled(coordinator.isRunning || !coordinator.hasActiveJob)

                Button(role: .destructive) {
                    coordinator.deleteSelectedJob()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(coordinator.isRunning || !isCurrentJobSaved)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07))
        }
    }

    private var jobEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Sync Job", systemImage: "arrow.trianglehead.2.clockwise")
                    .font(.headline)
                Spacer()
                Text(coordinator.job.dryRun ? "Dry run" : "Live")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((coordinator.job.dryRun ? Color.blue : Color.green).opacity(0.14), in: Capsule())
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text("Name")
                        .foregroundStyle(.secondary)
                    TextField("Job name", text: $coordinator.job.name)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Profiles")
                        .foregroundStyle(.secondary)
                    profileSelector
                }

                GridRow {
                    Text("Direction")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Direction", selection: $coordinator.job.direction) {
                            ForEach(TransferDirection.allCases) { direction in
                                Text(direction.label).tag(direction)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)

                        Text(coordinator.job.direction.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    Text(coordinator.job.direction == .download ? "Local destination" : "Local source")
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("Local folder", text: $coordinator.job.localPath)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            coordinator.chooseLocalFolder()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Choose folder")
                    }
                }

                GridRow {
                    Text("Shared Drive")
                        .foregroundStyle(.secondary)
                    TextField("Shared Drive or root folder name", text: Binding(
                        get: { coordinator.job.remoteRootName ?? "" },
                        set: { coordinator.job.remoteRootName = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text(coordinator.job.direction == .download ? "Drive source" : "Drive destination")
                        .foregroundStyle(.secondary)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Drive root or folder path", text: $coordinator.job.remotePath)
                                .textFieldStyle(.roundedBorder)
                            Text(destinationPreview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Button {
                            coordinator.openRemoteBrowser()
                        } label: {
                            Label("Browse", systemImage: "folder.badge.gearshape")
                        }
                        .disabled(coordinator.remotes.isEmpty)
                    }
                }

                GridRow {
                    Text("Mode")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Mode", selection: $coordinator.job.mode) {
                            ForEach(SyncMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(coordinator.job.mode.description)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let warning = coordinator.job.mode.warning {
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                GridRow {
                    Text("Workers")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 18) {
                            Stepper("Transfers: \(coordinator.job.transfers)", value: $coordinator.job.transfers, in: 1...64)
                                .frame(width: 180, alignment: .leading)
                            Stepper("Checkers: \(coordinator.job.checkers)", value: $coordinator.job.checkers, in: 1...128)
                                .frame(width: 180, alignment: .leading)
                            Toggle("Dry run", isOn: $coordinator.job.dryRun)
                                .toggleStyle(.switch)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Transfers controls how many files rclone uploads or downloads at the same time.")
                            Text("Checkers controls how many files rclone scans and compares in parallel before transfer.")
                            Label("Higher values can improve throughput, but they can also increase Google Drive API pressure.", systemImage: "gauge.with.dots.needle.67percent")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isCurrentJobSaved ? "Saved job" : "Unsaved job")
                        .font(.callout.weight(.medium))
                    Text("Save this configuration before starting if you want to reuse it later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    coordinator.saveCurrentJob()
                } label: {
                    Label("Save Job", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.isRunning)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07))
        }
    }

    private var noJobSelected: some View {
        VStack(alignment: .leading, spacing: 14) {
            if coordinator.runs.isEmpty {
                if let interruptedRun = coordinator.interruptedRun {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Restart Available", systemImage: "playpause.circle")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(interruptedRun.job.name)
                            .font(.title3.weight(.semibold))
                        Text("GDriveVault saved this interrupted run. Restart reruns the same sync profile so rclone can skip completed files. A partial Google Drive upload from a closed app starts that file again.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button {
                            coordinator.resume()
                        } label: {
                            Label("Restart Sync", systemImage: "playpause.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
                } else {
                    ContentUnavailableView(
                        "No sync profile selected",
                        systemImage: "tray.full",
                        description: Text("Choose a saved sync profile above or click New to create one.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            } else {
                HStack {
                    Label(coordinator.isRunning ? "Running Sync Profile" : "Last Sync Status", systemImage: coordinator.isRunning ? "arrow.triangle.2.circlepath" : "clock")
                        .font(.headline)
                    Spacer()
                    Text(coordinator.job.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                ForEach(coordinator.runs) { run in
                    RunRow(run: run)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07))
        }
    }

    private var isCurrentJobSaved: Bool {
        coordinator.savedJobs.contains { $0.id == coordinator.job.id }
    }

    private var destinationPreview: String {
        let rootName = coordinator.job.remoteRootName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = rootName?.isEmpty == false ? rootName! : "MrHandPay"
        let path = coordinator.job.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? root : "\(root)/\(path)"
    }

    private var profileSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(coordinator.job.selectedRemoteNames.count) selected")
                    .font(.callout.weight(.medium))
                Spacer()
                Button {
                    coordinator.refreshRemotes()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(coordinator.isRefreshing)
                Button {
                    coordinator.openProfileEditor()
                } label: {
                    Label("Manage", systemImage: "slider.horizontal.3")
                }
            }

            if coordinator.remotes.isEmpty {
                ContentUnavailableView("No profiles", systemImage: "externaldrive.badge.questionmark", description: Text("Add or import rclone profiles, then select accounts for this sync."))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(coordinator.remotes) { remote in
                        Toggle(isOn: Binding(
                            get: { coordinator.job.selectedRemoteNames.contains(remote.name) },
                            set: { _ in coordinator.toggleRemote(remote) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(remote.displayName)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(TransferStatsParser.formatBytes(coordinator.usage(for: remote.name).remainingBytes) + " left in window")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Text("Selected profiles form the failover pool, so GDriveVault can continue with the next account when a profile reaches its 750 GB quota window.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var runList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Runs")
                .font(.headline)

            if coordinator.runs.isEmpty {
                ContentUnavailableView("No runs yet", systemImage: "terminal", description: Text("Pick remotes and start a job to stream rclone output here."))
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ForEach(coordinator.runs) { run in
                    RunRow(run: run)
                }
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 42, height: 42)
                .background(Color.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07))
        }
    }
}

private struct SidebarMetric: View {
    let icon: String
    let value: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SavedJobRow: View {
    let job: SyncJob
    let isSelected: Bool
    let isRunning: Bool
    let isPaused: Bool
    let isAnyRunning: Bool
    let onEdit: () -> Void
    let onRun: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    Label(job.direction.label, systemImage: job.direction == .download ? "arrow.down.circle" : "arrow.up.circle")
                    Label(job.mode.label, systemImage: "switch.2")
                    Label("\(job.selectedRemoteNames.count)", systemImage: "person.2")
                    Label(job.dryRun ? "Dry" : "Live", systemImage: job.dryRun ? "eye" : "bolt.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(minWidth: 150, maxWidth: 220, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Label(job.localPath, systemImage: "folder")
                Label(displayDestination, systemImage: "cloud")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .disabled(isAnyRunning)

            if isRunning {
                if isPaused {
                    Button {
                        onResume()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        onPause()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    onStop()
                } label: {
                    Label("Cancel Job", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    onRun()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnyRunning)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(isSelected || isRunning ? 0.35 : 0.08))
        }
    }

    private var statusLabel: String {
        if isRunning { return "Running" }
        if isSelected { return "Editing" }
        return "Ready"
    }

    private var statusIcon: String {
        if isRunning { return "arrow.triangle.2.circlepath" }
        if isSelected { return "checkmark.circle.fill" }
        return "circle"
    }

    private var displayDestination: String {
        let rootName = job.remoteRootName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = rootName?.isEmpty == false ? rootName! : "MrHandPay"
        let path = job.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? root : "\(root)/\(path)"
    }

    private var statusColor: Color {
        if isRunning { return .green }
        if isSelected { return .blue }
        return .secondary
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06))
        }
    }
}

private struct LiveMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AccountUsageTile: View {
    let usage: AccountUsage
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(usage.remoteName.trimmingCharacters(in: CharacterSet(charactersIn: ":")), systemImage: usage.isAtCapacity ? "exclamationmark.triangle.fill" : "person.crop.circle.badge.checkmark")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(usage.isAtCapacity ? .orange : .primary)
                Spacer()
                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset this account")
            }

            ProgressView(value: usage.fractionUsed)
                .tint(usage.isAtCapacity ? .orange : .blue)

            HStack {
                Text("\(TransferStatsParser.formatBytes(usage.bytesTransferred)) used")
                Spacer()
                Text("\(TransferStatsParser.formatBytes(usage.remainingBytes)) left")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke((usage.isAtCapacity ? Color.orange : Color.primary).opacity(0.10))
        }
    }
}

private struct ConnectionCheckPanel: View {
    @EnvironmentObject private var coordinator: SyncCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Connection Check", systemImage: "network")
                    .font(.headline)
                Spacer()
                Button {
                    coordinator.runBandwidthTest()
                } label: {
                    if coordinator.isRunningBandwidthTest {
                        Label("Testing", systemImage: "hourglass")
                    } else {
                        Label("Test Now", systemImage: "speedometer")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.isRunningBandwidthTest || coordinator.isRunning)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                LiveMetric(title: "Download", value: downloadText, icon: "arrow.down.circle")
                LiveMetric(title: "Upload", value: uploadText, icon: "arrow.up.circle")
                LiveMetric(title: "Sample", value: sampleText, icon: "externaldrive")
                LiveMetric(title: "Last tested", value: coordinator.latestBandwidthTest?.displayTime ?? "Not tested", icon: "clock")
            }

            if let result = coordinator.latestBandwidthTest {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsInfoRow(label: "Public IP", value: result.publicIP ?? "Unavailable")
                    SettingsInfoRow(label: "Location", value: result.location ?? "Unavailable")
                    SettingsInfoRow(label: "Provider", value: result.provider ?? "Unavailable")
                    SettingsInfoRow(label: "Endpoint", value: result.endpoint)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            Text("GDriveVault posts the latest download speed, upload speed, public IP, and location metadata to GDriveVault Control with the agent heartbeat when available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07))
        }
    }

    private var downloadText: String {
        if coordinator.isRunningBandwidthTest {
            return "Testing"
        }
        return coordinator.latestBandwidthTest?.displaySpeed ?? "No test"
    }

    private var uploadText: String {
        if coordinator.isRunningBandwidthTest {
            return "Testing"
        }
        return coordinator.latestBandwidthTest?.displayUploadSpeed ?? "No test"
    }

    private var sampleText: String {
        guard let result = coordinator.latestBandwidthTest else { return "-" }
        if let uploaded = result.bytesUploaded {
            return "\(TransferStatsParser.formatBytes(result.bytesDownloaded)) down / \(TransferStatsParser.formatBytes(uploaded)) up"
        }
        return TransferStatsParser.formatBytes(result.bytesDownloaded)
    }
}

private struct AccountTrackerPanel: View {
    @EnvironmentObject private var coordinator: SyncCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Account Tracker", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.headline)
                Spacer()
                Text("750 GB per profile, last 24 hours")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Button {
                    coordinator.resetAllUsage()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset all usage")
            }

            if coordinator.accountUsages.isEmpty {
                ContentUnavailableView("No accounts tracked", systemImage: "gauge", description: Text("Refresh profiles to start tracking transfer usage."))
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(coordinator.accountUsages) { usage in
                        AccountUsageTile(usage: usage) {
                            coordinator.resetUsage(for: usage.remoteName)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07))
        }
    }
}

private struct BackupSettingsPanel: View {
    @EnvironmentObject private var coordinator: SyncCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Backup & Restore", systemImage: "archivebox")
                .font(.headline)

            SettingsActionRow(
                icon: "archivebox",
                title: "Export Local Backup",
                subtitle: "Save profiles, sync jobs, usage, and integrations",
                isDisabled: coordinator.isRunning || coordinator.isUploadingSettingsBackup
            ) {
                coordinator.backupSettings()
            }

            SettingsActionRow(
                icon: "icloud.and.arrow.up",
                title: coordinator.isUploadingSettingsBackup ? "Uploading Backup" : "Push Backup to Control Server",
                subtitle: coordinator.remoteControlSettings.isRegistered ? "Store app settings and rclone profiles remotely" : "Register this Mac first",
                isDisabled: coordinator.isRunning || coordinator.isUploadingSettingsBackup || !coordinator.remoteControlSettings.isRegistered
            ) {
                coordinator.uploadSettingsBackupToControlServer()
            }

            SettingsActionRow(
                icon: "arrow.counterclockwise.circle",
                title: "Restore From Backup",
                subtitle: "Import a GDriveVault backup file",
                isDisabled: coordinator.isRunning || coordinator.isUploadingSettingsBackup
            ) {
                coordinator.restoreSettings()
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07))
        }
    }
}

private struct OrganizationBrandingPanel: View {
    @EnvironmentObject private var coordinator: SyncCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                BrandingLogoView(path: coordinator.organizationBranding.logoPath, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(coordinator.organizationBranding.isConfigured ? coordinator.organizationBranding.displayName : "No organization branding")
                        .font(.title3.weight(.semibold))
                    Text(coordinator.organizationBranding.isConfigured ? coordinator.organizationBranding.managedStatement : "Add an organization name and optional logo for managed deployments.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Organization")
                        .foregroundStyle(.secondary)
                    TextField("Organization name", text: $coordinator.organizationBranding.organizationName)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Managed by")
                        .foregroundStyle(.secondary)
                    TextField("Managed by name", text: $coordinator.organizationBranding.managedByName)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Logo")
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(coordinator.organizationBranding.logoPath.isEmpty ? "No logo selected" : coordinator.organizationBranding.logoPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            coordinator.chooseOrganizationLogo()
                        } label: {
                            Label("Choose", systemImage: "photo")
                        }
                        Button {
                            coordinator.clearOrganizationLogo()
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                        .disabled(coordinator.organizationBranding.logoPath.isEmpty)
                    }
                }
            }

            HStack {
                Text("This does not replace GDriveVault branding. It adds a licensed-to / managed-by identity for organizations using the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    coordinator.organizationBranding = .empty
                    coordinator.saveOrganizationBranding()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                Button {
                    coordinator.saveOrganizationBranding()
                } label: {
                    Label("Save Branding", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.07))
        }
    }
}

private struct BrandingLogoView: View {
    let path: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: max(18, size * 0.52)))
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: size, height: size)
        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08))
        }
    }

    private var image: NSImage? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return NSImage(contentsOfFile: trimmed)
    }
}

private struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

private enum SettingsModal: String, Identifiable {
    case connection
    case accounts
    case backup
    case branding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: "Connection Check"
        case .accounts: "Account Usage"
        case .backup: "Backup & Restore"
        case .branding: "Organization Branding"
        }
    }

    var icon: String {
        switch self {
        case .connection: "network"
        case .accounts: "gauge.with.dots.needle.50percent"
        case .backup: "archivebox"
        case .branding: "building.2.crop.circle"
        }
    }
}

private struct SettingsModalView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @Environment(\.dismiss) private var dismiss
    let modal: SettingsModal

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: modal.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

                Text(modal.title)
                    .font(.title2.weight(.semibold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            ScrollView {
                modalContent
                    .padding(20)
            }
        }
    }

    @ViewBuilder
    private var modalContent: some View {
        switch modal {
        case .connection:
            ConnectionCheckPanel()
        case .accounts:
            AccountTrackerPanel()
        case .backup:
            BackupSettingsPanel()
        case .branding:
            OrganizationBrandingPanel()
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @Environment(\.dismiss) private var dismiss
    @Binding var isWelcomeShown: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Image("gdrivevault-hero", bundle: .gdriveVaultResources)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 190)
                    .clipped()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.66),
                        Color.black.opacity(0.28),
                        Color.clear
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to GDriveVault")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                    Text("A faster, more powerful way to manage your Google Drive files on macOS.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.90))
                }
                .padding(24)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Welcome to GDriveVault--a faster, more powerful way to manage your Google Drive files on macOS.")
                        .font(.title3.weight(.semibold))

                    Text("Built for users who need more than the standard Google Drive desktop application, GDriveVault delivers enhanced performance, greater flexibility, and advanced file management tools designed to make working with cloud storage faster and easier.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if coordinator.organizationBranding.isConfigured {
                        HStack(spacing: 12) {
                            BrandingLogoView(path: coordinator.organizationBranding.logoPath, size: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(coordinator.organizationBranding.displayName)
                                    .font(.headline)
                                Text(coordinator.organizationBranding.managedStatement)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Key Features")
                            .font(.headline)

                        WelcomeFeature(icon: "arrow.up.arrow.down.circle.fill", title: "High-speed uploads and downloads", detail: "Optimized transfer performance for moving files quickly.")
                        WelcomeFeature(icon: "slider.horizontal.3", title: "Advanced synchronization", detail: "Greater control over how your files move between your Mac and Google Drive.")
                        WelcomeFeature(icon: "checklist", title: "Selective syncing", detail: "Choose specific folders and files to save storage and bandwidth.")
                        WelcomeFeature(icon: "clock.arrow.circlepath", title: "Automatic background syncing", detail: "Keep your files up to date with less manual work.")
                        WelcomeFeature(icon: "chart.line.uptrend.xyaxis", title: "Detailed progress and logs", detail: "See transfer status, activity history, and what happened after each run.")
                        WelcomeFeature(icon: "exclamationmark.shield.fill", title: "Smart conflict handling", detail: "Designed to help prevent data loss during complex file movement.")
                        WelcomeFeature(icon: "externaldrive.connected.to.line.below", title: "Reliable transfer engine", detail: "Efficiently handles large files and extensive file libraries.")
                        WelcomeFeature(icon: "macwindow", title: "Native macOS experience", detail: "Fits into your workflow with focused Mac-first controls.")
                    }

                    Text("Whether you're syncing personal documents, collaborating with a team, or managing terabytes of data, GDriveVault is designed to provide a faster, more reliable, and more feature-rich Google Drive experience.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Thank you for choosing GDriveVault. We hope it becomes your preferred way to work with Google Drive.")
                        .font(.callout.weight(.semibold))
                }
                .padding(24)
            }

            Divider()

            HStack {
                Text("You can continue setup after this welcome screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isWelcomeShown = true
                    dismiss()
                } label: {
                    Label("Get Started", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
    }
}

private struct WelcomeFeature: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FullDiskAccessGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isSetupComplete: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Grant Mac Access")
                        .font(.title2.weight(.semibold))
                    Text("Allow GDriveVault to work without repeated folder prompts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                Text("macOS protects folders like Downloads, Desktop, Documents, removable drives, and app update locations. Full Disk Access lets GDriveVault run syncs, downloads, logs, backups, and forced updates without stopping for access prompts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    PermissionStep(number: "1", title: "Open Full Disk Access", subtitle: "GDriveVault will open the correct System Settings page.")
                    PermissionStep(number: "2", title: "Add GDriveVault if it is missing", subtitle: "If GDriveVault is not listed, click the + button, choose GDriveVault.app, and approve the prompt.")
                    PermissionStep(number: "3", title: "Enable GDriveVault", subtitle: "Turn on the switch next to GDriveVault. You may need to unlock System Settings first.")
                    PermissionStep(number: "4", title: "Restart GDriveVault if macOS asks", subtitle: "The permission takes effect after macOS accepts the change.")
                }

                HStack(spacing: 12) {
                    Button {
                        openFullDiskAccessSettings()
                    } label: {
                        Label("Open Full Disk Access", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    } label: {
                        Label("Reveal GDriveVault.app", systemImage: "app")
                    }
                    .help("Use this to find the app when adding it with the + button.")
                }

                Text("If GDriveVault is not shown in the list, add it manually with the + button. Apple does not allow apps to grant this permission silently.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Spacer()

            Divider()

            HStack {
                Button("Remind Me Later") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    isSetupComplete = true
                    dismiss()
                } label: {
                    Label("I Granted Access", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct PermissionStep: View {
    let number: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.blue, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AppSettingsView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @Binding var selectedPage: AppPage
    @Binding var isPresented: Bool
    let onOpenFullDiskAccessGuide: () -> Void
    @State private var activeModal: SettingsModal?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                    Text("GDriveVault configuration")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsGroup(title: "Sync") {
                        SettingsActionRow(
                            icon: "slider.horizontal.3",
                            title: "Sync Profiles",
                            subtitle: "Saved sync profiles and job setup"
                        ) {
                            selectedPage = .syncSettings
                            isPresented = false
                        }
                    }

                    SettingsGroup(title: "Diagnostics") {
                        SettingsActionRow(
                            icon: "network",
                            title: "Connection Check",
                            subtitle: coordinator.latestBandwidthTest?.displayTime ?? "Run speed, IP, and location check"
                        ) {
                            activeModal = .connection
                        }

                        SettingsActionRow(
                            icon: "gauge.with.dots.needle.50percent",
                            title: "Account Usage",
                            subtitle: "\(coordinator.accountUsages.count) profiles tracked against the 750 GB daily limit"
                        ) {
                            activeModal = .accounts
                        }

                        SettingsActionRow(
                            icon: "lock.shield",
                            title: "Mac Permissions",
                            subtitle: "Grant Full Disk Access to avoid folder prompts during updates and transfers"
                        ) {
                            onOpenFullDiskAccessGuide()
                        }
                    }

                    SettingsGroup(title: "Rclone") {
                        SettingsActionRow(
                            icon: "externaldrive.badge.gearshape",
                            title: "Rclone Profile Settings",
                            subtitle: coordinator.configPath.isEmpty ? "Profile editor" : coordinator.configPath
                        ) {
                            closeThen {
                                coordinator.openProfileEditor()
                            }
                        }

                        SettingsActionRow(
                            icon: "square.and.arrow.down",
                            title: "Import Rclone Profiles",
                            subtitle: "Import another rclone config file"
                        ) {
                            closeThen {
                                coordinator.openProfileImporter()
                            }
                        }
                    }

                    SettingsGroup(title: "Backup") {
                        SettingsActionRow(
                            icon: "archivebox",
                            title: "Backup & Restore",
                            subtitle: "Export, restore, or push settings to GDriveVault Control",
                            isDisabled: coordinator.isRunning || coordinator.isUploadingSettingsBackup
                        ) {
                            activeModal = .backup
                        }
                    }

                    SettingsGroup(title: "Branding") {
                        SettingsActionRow(
                            icon: "building.2.crop.circle",
                            title: "Organization Branding",
                            subtitle: coordinator.organizationBranding.isConfigured ? coordinator.organizationBranding.managedStatement : "Add a licensed-to or managed-by organization logo"
                        ) {
                            activeModal = .branding
                        }
                    }

                    SettingsGroup(title: "Integrations") {
                        SettingsActionRow(
                            icon: "antenna.radiowaves.left.and.right",
                            title: "Remote Control",
                            subtitle: coordinator.remoteControlSettings.isRegistered ? coordinator.remoteControlStatus : "Pair this Mac with GDriveVault Control"
                        ) {
                            closeThen {
                                coordinator.openRemoteControlSettings()
                            }
                        }

                        SettingsActionRow(
                            icon: "message.badge",
                            title: "Google Chat Spaces",
                            subtitle: coordinator.googleChatSettings.isConfigured ? "Connected" : "Not configured"
                        ) {
                            closeThen {
                                coordinator.openGoogleChatSettings()
                            }
                        }

                        SettingsActionRow(
                            icon: "arrow.down.circle",
                            title: "Check for Updates",
                            subtitle: "Current version \(AppVersion.current)",
                            isDisabled: coordinator.isCheckingForUpdates
                        ) {
                            coordinator.checkForUpdates(showUpToDate: true)
                        }
                    }
                }
                .padding(20)
            }
        }
        .sheet(item: $activeModal) { modal in
            SettingsModalView(modal: modal)
                .environmentObject(coordinator)
                .frame(minWidth: 700, minHeight: 520)
        }
    }

    private func closeThen(_ action: @escaping () -> Void) {
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            action()
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                content
            }
        }
    }
}

private struct SettingsActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isDisabled ? Color.secondary : Color.blue)
                    .frame(width: 36, height: 36)
                    .background((isDisabled ? Color.primary : Color.blue).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

private struct RemoteBrowserView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @Environment(\.dismiss) private var dismiss

    private var browserLocation: String {
        let path = coordinator.browserPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? "\(coordinator.browserRemoteName) root" : "\(coordinator.browserRemoteName)\(path)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Remote Destination")
                        .font(.title2.weight(.semibold))
                    Text(browserLocation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Picker("Profile", selection: Binding(
                    get: { coordinator.browserRemoteName },
                    set: { coordinator.selectBrowserRemote($0) }
                )) {
                    ForEach(coordinator.remotes) { remote in
                        Text(remote.displayName).tag(remote.name)
                    }
                }
                .frame(width: 220)

                Button {
                    coordinator.loadRemoteFolders()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh folder list")
                .disabled(coordinator.isLoadingRemoteFolders)
            }
            .padding(20)

            Divider()

            HStack(spacing: 12) {
                Button {
                    coordinator.goToParentRemoteFolder()
                } label: {
                    Label("Up", systemImage: "chevron.up")
                }
                .disabled(coordinator.browserPath.isEmpty || coordinator.isLoadingRemoteFolders)

                Text(coordinator.browserPath.isEmpty ? "/" : "/\(coordinator.browserPath)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if coordinator.isLoadingRemoteFolders {
                ProgressView("Loading folders...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if coordinator.remoteFolders.isEmpty {
                ContentUnavailableView("No folders here", systemImage: "folder", description: Text("Use this location or refresh after changing the profile."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(coordinator.remoteFolders) { folder in
                    Button {
                        coordinator.openRemoteFolder(folder)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name)
                                    .font(.callout.weight(.medium))
                                Text(folder.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 5)
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Text("Selected: \(browserLocation)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    coordinator.useCurrentRemoteFolder()
                } label: {
                    Label("Use Folder", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(coordinator.browserRemoteName.isEmpty)
            }
            .padding(20)
        }
    }
}

private struct RemoteDownloadBrowserView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @Environment(\.dismiss) private var dismiss

    private var browserLocation: String {
        let path = coordinator.browserPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? "\(coordinator.browserRemoteName) root" : "\(coordinator.browserRemoteName)\(path)"
    }

    private var selectedCount: Int {
        coordinator.selectedRemoteItemIDs.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.folder.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Drive Browser")
                        .font(.title2.weight(.semibold))
                    Text(browserLocation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Picker("Profile", selection: Binding(
                    get: { coordinator.browserRemoteName },
                    set: { coordinator.selectDownloadBrowserRemote($0) }
                )) {
                    ForEach(coordinator.remotes) { remote in
                        Text(remote.displayName).tag(remote.name)
                    }
                }
                .frame(width: 220)

                Button {
                    coordinator.loadRemoteItems()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh file list")
                .disabled(coordinator.isLoadingRemoteItems)
            }
            .padding(20)

            Divider()

            HStack(spacing: 12) {
                Button {
                    coordinator.goToParentDownloadFolder()
                } label: {
                    Label("Up", systemImage: "chevron.up")
                }
                .disabled(coordinator.browserPath.isEmpty || coordinator.isLoadingRemoteItems)

                Text(coordinator.browserPath.isEmpty ? "/" : "/\(coordinator.browserPath)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("\(selectedCount) selected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if coordinator.isLoadingRemoteItems {
                ProgressView("Loading Drive files...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if coordinator.remoteItems.isEmpty {
                ContentUnavailableView("No files here", systemImage: "folder", description: Text("Refresh or choose another folder."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(coordinator.remoteItems) { item in
                    RemoteDownloadItemRow(
                        item: item,
                        isSelected: coordinator.selectedRemoteItemIDs.contains(item.id),
                        onToggle: {
                            coordinator.toggleRemoteItemSelection(item)
                        },
                        onOpen: {
                            coordinator.openDownloadFolder(item)
                        }
                    )
                    .padding(.vertical, 5)
                }
                .listStyle(.inset)
            }

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text("Download to")
                        .foregroundStyle(.secondary)
                    Text(coordinator.downloadLocalPath)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        coordinator.chooseDownloadDestination()
                    } label: {
                        Label("Choose", systemImage: "folder")
                    }
                }

                HStack {
                    Text("Selected items will download using the selected sync profiles as a failover pool.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button {
                        coordinator.startSelectedRemoteDownload()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedCount == 0 || coordinator.downloadLocalPath.isEmpty || coordinator.isRunning || coordinator.isRunningBandwidthTest)
                }
            }
            .padding(20)
        }
    }
}

private struct RemoteDownloadItemRow: View {
    let item: RemoteItem
    let isSelected: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Remove from download" : "Add to download")

            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(item.isDirectory ? "Folder" : TransferStatsParser.formatBytes(item.size ?? 0))
                    if let modified = item.modified {
                        Text("Modified \(modified.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if item.isDirectory {
                Button(action: onOpen) {
                    Label("Open", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Open folder")
            }
        }
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    if item.isDirectory {
                        onOpen()
                    } else {
                        onToggle()
                    }
                }
                .exclusively(before: TapGesture().onEnded {
                    onToggle()
                })
        )
    }
}

private struct DownloadTransferWindow: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Download")
                        .font(.title2.weight(.semibold))
                    Text(coordinator.job.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if coordinator.isRunning {
                    if coordinator.isPaused {
                        Button {
                            coordinator.continuePausedRun()
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            coordinator.stop()
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                    }

                    Button(role: .destructive) {
                        coordinator.cancelJob()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                } else if coordinator.canResume {
                    Button {
                        coordinator.resume()
                    } label: {
                        Label("Resume", systemImage: "playpause.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        LiveMetric(title: "Destination", value: coordinator.job.localPath, icon: "folder")
                        LiveMetric(title: "Speed", value: TransferStatsParser.formatSpeed(coordinator.runs.last?.progress?.speedBytesPerSecond), icon: "speedometer")
                        LiveMetric(title: "ETA", value: coordinator.runs.last?.progress?.eta ?? "-", icon: "timer")
                    }

                    if coordinator.runs.isEmpty {
                        ContentUnavailableView("Preparing download", systemImage: "hourglass", description: Text(coordinator.statusMessage))
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        ForEach(coordinator.runs) { run in
                            RunRow(run: run)
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

private struct ProfileEditorView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GDriveVault Profiles")
                        .font(.title2.weight(.semibold))
                    Text(coordinator.configPath.isEmpty ? "Loading config file..." : coordinator.configPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button {
                    coordinator.loadProfiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload config")
                .disabled(coordinator.isLoadingProfiles || coordinator.isSavingProfiles)

                Button {
                    coordinator.openConfigWizard()
                } label: {
                    Label("Wizard", systemImage: "terminal")
                }
                .disabled(coordinator.isLoadingProfiles || coordinator.isSavingProfiles)

                Button {
                    coordinator.importProfiles()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .disabled(coordinator.isLoadingProfiles || coordinator.isSavingProfiles)

                Button {
                    coordinator.addProfile()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(coordinator.isLoadingProfiles || coordinator.isSavingProfiles)
            }
            .padding(20)

            Divider()

            if coordinator.isLoadingProfiles {
                ProgressView("Loading profiles...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if coordinator.profileDrafts.isEmpty {
                ContentUnavailableView("No profiles", systemImage: "externaldrive.badge.plus", description: Text("Add a profile and save it to create an rclone config."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach($coordinator.profileDrafts) { $profile in
                            ProfileSectionView(profile: $profile) {
                                coordinator.addEntry(to: profile)
                            } onDelete: {
                                coordinator.deleteProfile(profile)
                            }
                        }
                    }
                    .padding(20)
                }
            }

            Divider()

            HStack {
                Text("A backup is created before every save.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    coordinator.saveProfiles()
                } label: {
                    if coordinator.isSavingProfiles {
                        Label("Saving", systemImage: "hourglass")
                    } else {
                        Label("Save", systemImage: "checkmark")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(coordinator.isSavingProfiles || coordinator.configPath.isEmpty)
            }
            .padding(20)
        }
        .sheet(isPresented: $coordinator.isConfigWizardPresented) {
            ConfigWizardView()
                .environmentObject(coordinator)
                .frame(minWidth: 820, minHeight: 620)
        }
    }
}

private struct GoogleChatSettingsView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "message.badge.filled.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Google Chat Space")
                        .font(.title2.weight(.semibold))
                    Text("Post sync updates to a team Space using an incoming webhook.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                Section {
                    SecureField("Google Chat webhook URL", text: $coordinator.googleChatSettings.webhookURL)
                        .textFieldStyle(.roundedBorder)
                    Text("Create an incoming webhook in the target Space, then paste its URL here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Space Webhook")
                }

                Section {
                    Toggle("Notify when a sync starts", isOn: $coordinator.googleChatSettings.notifyStarted)
                    Toggle("Notify when a sync completes", isOn: $coordinator.googleChatSettings.notifyCompleted)
                    Toggle("Notify when a sync fails, cancels, or exhausts the failover pool", isOn: $coordinator.googleChatSettings.notifyFailed)
                    Toggle("Batch completed-file updates", isOn: $coordinator.googleChatSettings.notifyCompletedFiles)

                    Stepper(
                        "Send file batches every \(coordinator.googleChatSettings.fileBatchSize) files",
                        value: $coordinator.googleChatSettings.fileBatchSize,
                        in: 1...50
                    )
                    .disabled(!coordinator.googleChatSettings.notifyCompletedFiles)

                    Text("GDriveVault sends throttled progress updates automatically. Completed-file batches depend on rclone emitting copied-file log lines and keep the Space readable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Notifications")
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            HStack {
                Text(coordinator.googleChatSettings.isConfigured ? "Google Chat notifications are configured." : "Notifications are disabled until a webhook URL is saved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    coordinator.testGoogleChat()
                } label: {
                    if coordinator.isTestingGoogleChat {
                        Label("Testing", systemImage: "hourglass")
                    } else {
                        Label("Test", systemImage: "paperplane")
                    }
                }
                .disabled(coordinator.isTestingGoogleChat || !coordinator.googleChatSettings.isConfigured)

                Button {
                    coordinator.saveGoogleChatSettings()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
    }
}

private struct RemoteControlSettingsView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: coordinator.requiresRegistration ? "key.fill" : "antenna.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(coordinator.requiresRegistration ? .orange : .blue)
                    .frame(width: 44, height: 44)
                    .background((coordinator.requiresRegistration ? Color.orange : Color.blue).opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(coordinator.requiresRegistration ? "GDriveVault License" : "Remote Control")
                        .font(.title2.weight(.semibold))
                    Text(coordinator.requiresRegistration ? "Activate this Mac before GDriveVault can be used." : "Pair this Mac with GDriveVault Control for status and commands.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                Section {
                    HStack {
                        Text("Server URL")
                        Spacer()
                        Text(RemoteControlSettings.productionServerURL)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    TextField("Device name", text: $coordinator.remoteControlSettings.deviceName)
                        .textFieldStyle(.roundedBorder)
                    SecureField("License key", text: $coordinator.remoteControlSettings.licenseKey)
                        .textFieldStyle(.roundedBorder)

                    Stepper(
                        "Poll every \(coordinator.remoteControlSettings.pollIntervalSeconds) seconds",
                        value: $coordinator.remoteControlSettings.pollIntervalSeconds,
                        in: 2...60
                    )
                } header: {
                    Text("License")
                }

                Section {
                    if coordinator.requiresRegistration {
                        Label("GDriveVault is disabled until this Mac is registered with a valid license key.", systemImage: "lock.trianglebadge.exclamationmark")
                            .foregroundStyle(coordinator.isLicenseLocked ? .red : .orange)
                    }
                    Label("Remote control is always enabled for licensed agents.", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)

                    if coordinator.organizationBranding.isConfigured {
                        HStack(spacing: 10) {
                            BrandingLogoView(path: coordinator.organizationBranding.logoPath, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(coordinator.organizationBranding.displayName)
                                    .font(.callout.weight(.semibold))
                                Text(coordinator.organizationBranding.managedStatement)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack {
                        Label(coordinator.remoteControlSettings.isRegistered ? "Registered" : "Not registered", systemImage: coordinator.remoteControlSettings.isRegistered ? "checkmark.seal.fill" : "exclamationmark.triangle")
                            .foregroundStyle(coordinator.remoteControlSettings.isRegistered ? .green : .orange)
                        Spacer()
                        if let deviceID = coordinator.remoteControlSettings.deviceID {
                            Text(deviceID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    if let approvalRequestID = coordinator.remoteControlSettings.approvalRequestID, !approvalRequestID.isEmpty {
                        HStack {
                            Label("Waiting for approval", systemImage: "person.badge.clock")
                                .foregroundStyle(.orange)
                            Spacer()
                            Text(approvalRequestID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    Text(coordinator.remoteControlStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Activation")
                }

                if coordinator.remoteControlSettings.isRegistered {
                    Section {
                        Text("Supported commands: start_current, start_job, stop, resume, cancel_job, refresh_remotes, and check_updates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Commands")
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            HStack {
                Spacer()

                Button(coordinator.requiresRegistration ? "Quit" : "Cancel") {
                    if coordinator.requiresRegistration {
                        quitUnregisteredApplication()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    coordinator.registerRemoteControlDevice()
                } label: {
                    if coordinator.isRegisteringRemoteControl && !coordinator.isAutomaticRemoteRegistration {
                        Label("Registering", systemImage: "hourglass")
                    } else if coordinator.remoteControlSettings.isPendingApproval {
                        Label(coordinator.isAutomaticRemoteRegistration ? "Waiting for Approval" : "Check Approval", systemImage: "person.badge.clock")
                    } else if !coordinator.remoteControlSettings.hasLicenseKey {
                        Label("Request Approval", systemImage: "person.badge.plus")
                    } else {
                        Label("Register", systemImage: "link")
                    }
                }
                .disabled(
                    coordinator.isRegisteringRemoteControl ||
                    coordinator.remoteControlSettings.serverURL.isEmpty ||
                    coordinator.remoteControlSettings.deviceName.isEmpty
                )

                if coordinator.remoteControlSettings.isRegistered {
                    Button {
                        coordinator.testRemoteControlConnection()
                    } label: {
                        if coordinator.isTestingRemoteControl {
                            Label("Testing", systemImage: "hourglass")
                        } else {
                            Label("Test", systemImage: "network")
                        }
                    }
                    .disabled(coordinator.isTestingRemoteControl)

                    Button {
                        coordinator.saveRemoteControlSettings()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    private func quitUnregisteredApplication() {
        NSApplication.shared.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            Darwin.exit(0)
        }
    }
}

private struct ConfigWizardView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rclone Config Wizard")
                        .font(.title2.weight(.semibold))
                    Text("Use the same menu flow as Terminal, without leaving the app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    coordinator.configSession.start {
                        coordinator.loadProfiles()
                        coordinator.refreshRemotes()
                    }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    coordinator.configSession.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!coordinator.configSession.isRunning)
            }
            .padding(20)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(coordinator.configSession.output.isEmpty ? "Starting rclone config..." : coordinator.configSession.output)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .id("wizard-output")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: coordinator.configSession.output) {
                    proxy.scrollTo("wizard-output", anchor: .bottom)
                }
            }

            Divider()

            HStack(spacing: 10) {
                TextField("Type a menu choice or answer, then press Return", text: $coordinator.configSession.input)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .onSubmit {
                        coordinator.configSession.sendInput()
                    }
                    .disabled(!coordinator.configSession.isRunning)

                Button {
                    coordinator.configSession.sendInput()
                    inputFocused = true
                } label: {
                    Label("Send", systemImage: "return")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!coordinator.configSession.isRunning)

                Button {
                    coordinator.closeConfigWizard()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
            }
            .padding(20)
        }
        .onAppear {
            inputFocused = true
        }
        .onDisappear {
            if coordinator.configSession.isRunning {
                coordinator.configSession.stop()
            }
        }
    }
}

private struct ProfileSectionView: View {
    @Binding var profile: RcloneProfileDraft
    let onAddEntry: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundStyle(.secondary)

                TextField("Profile name", text: $profile.name)
                    .font(.headline)
                    .textFieldStyle(.roundedBorder)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete profile")
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Key")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Value")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("")
                }

                ForEach($profile.entries) { $entry in
                    GridRow {
                        TextField("type", text: $entry.key)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                        TextField("drive", text: $entry.value)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            profile.entries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove setting")
                    }
                }
            }

            HStack {
                Button {
                    onAddEntry()
                } label: {
                    Label("Setting", systemImage: "plus")
                }

                Spacer()

                Text(typeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var typeSummary: String {
        if let type = profile.entries.first(where: { $0.key == "type" })?.value, !type.isEmpty {
            return "type = \(type)"
        }
        return "Add type = drive for Google Drive"
    }
}

private struct RunRow: View {
    let run: SyncRun

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(run.remoteName.trimmingCharacters(in: CharacterSet(charactersIn: ":")), systemImage: iconName)
                    .font(.headline)
                Spacer()
                if run.transferredBytes > 0 || run.maxTransferBytes != nil {
                    Text(runLimitSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(run.state.label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(stateColor)
            }

            if let progress = run.progress {
                VStack(alignment: .leading, spacing: 12) {
                    ProgressView(value: progress.fractionComplete)
                        .tint(stateColor)

                    HStack(spacing: 14) {
                        RunMetric(title: "Transferred", value: transferredSummary, icon: "arrow.up.doc")
                        RunMetric(title: "Speed", value: TransferStatsParser.formatSpeed(progress.speedBytesPerSecond), icon: "speedometer")
                        RunMetric(title: "ETA", value: progress.eta ?? "-", icon: "timer")
                        RunMetric(title: "Files", value: filesSummary, icon: "doc.on.doc")
                    }

                    if !progress.activeFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transferring")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(progress.activeFiles) { file in
                                ActiveFileRow(file: file)
                            }
                        }
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            if isResumableState {
                Label("Resume reruns this sync job and skips completed files. Cancelled partial Google Drive files restart from the beginning.", systemImage: "playpause")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let logFilePath = run.logFilePath {
                HStack(spacing: 10) {
                    Label("Saved log", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.semibold))
                    Text(logFilePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: logFilePath)])
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            DisclosureGroup {
                ScrollView {
                    Text(run.log.isEmpty ? "Waiting for rclone output..." : run.log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 120, maxHeight: 220)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            } label: {
                Label("Raw rclone log", systemImage: "terminal")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch run.state {
        case .running: "arrow.triangle.2.circlepath"
        case .cancelled: "stop.circle.fill"
        case .finished(let code): code == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        case .skipped: "forward.end.fill"
        case .failed: "xmark.octagon.fill"
        case .idle: "circle"
        }
    }

    private var stateColor: Color {
        switch run.state {
        case .running: .blue
        case .cancelled: .red
        case .finished(let code): code == 0 ? .green : .orange
        case .skipped: .orange
        case .failed: .red
        case .idle: .secondary
        }
    }

    private var runLimitSummary: String {
        let transferred = TransferStatsParser.formatBytes(run.transferredBytes)
        guard let maxTransferBytes = run.maxTransferBytes else {
            return "\(transferred) transferred"
        }

        return "\(transferred) / \(TransferStatsParser.formatBytes(maxTransferBytes))"
    }

    private var isResumableState: Bool {
        switch run.state {
        case .cancelled, .failed:
            true
        case .finished(let code):
            code != 0
        case .idle, .running, .skipped:
            false
        }
    }

    private var transferredSummary: String {
        guard let progress = run.progress else {
            return TransferStatsParser.formatBytes(run.transferredBytes)
        }

        if let totalBytes = progress.totalBytes {
            return "\(TransferStatsParser.formatBytes(progress.transferredBytes)) / \(TransferStatsParser.formatBytes(totalBytes))"
        }

        return TransferStatsParser.formatBytes(progress.transferredBytes)
    }

    private var filesSummary: String {
        guard let progress = run.progress,
              let filesDone = progress.filesDone,
              let filesTotal = progress.filesTotal
        else {
            return "-"
        }

        return "\(filesDone) / \(filesTotal) (\(TransferStatsParser.formatPercent(progress.filesPercent)))"
    }
}

private struct RunMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActiveFileRow: View {
    let file: ActiveFileTransfer

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(file.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(TransferStatsParser.formatPercent(file.percent)) • \(TransferStatsParser.formatSpeed(file.speedBytesPerSecond))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(file.percent ?? 0) / 100)
                .tint(.blue)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SyncCoordinator())
}
