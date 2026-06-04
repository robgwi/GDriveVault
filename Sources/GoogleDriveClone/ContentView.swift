import SwiftUI

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
        case .dashboard: "Account usage and live transfer health"
        case .syncSettings: "Saved sync profiles and job setup"
        case .status: "Run logs and failover history"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @State private var selectedPage: AppPage = .dashboard

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
        .navigationTitle("SkyVault for Google")
        .task {
            if coordinator.remotes.isEmpty {
                coordinator.refreshRemotes()
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
                    Text("SkyVault")
                        .font(.headline)
                    Text("for Google")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

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
                coordinator.openProfileEditor()
            } label: {
                Label("Manage Profiles", systemImage: "externaldrive.badge.gearshape")
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
                coordinator.backupSettings()
            } label: {
                Label("Backup", systemImage: "archivebox")
            }
            .controlSize(.large)

            Button {
                coordinator.restoreSettings()
            } label: {
                Label("Restore", systemImage: "arrow.counterclockwise.circle")
            }
            .controlSize(.large)
            .disabled(coordinator.isRunning)

            Button {
                coordinator.openProfileEditor()
            } label: {
                Label("Profiles", systemImage: "slider.horizontal.3")
            }
            .controlSize(.large)

            if coordinator.isRunning {
                Button(role: .destructive) {
                    coordinator.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                if coordinator.canResume {
                    Button {
                        coordinator.resume()
                    } label: {
                        Label("Resume", systemImage: "playpause.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Button {
                    coordinator.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!coordinator.hasRunnableJob)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .dashboard:
            VStack(alignment: .leading, spacing: 20) {
                hero
                quickStats
                liveTransferPanel
                accountTracker
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
            Image("skyvault-hero", bundle: .module)
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
                    Text("SkyVault for Google")
                        .font(.largeTitle.weight(.semibold))
                }

                Text("Coordinate multiple rclone profiles for fast, resilient Google Drive movement.")
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
            StatTile(title: "Live", value: liveTransferredText, icon: coordinator.isRunning ? "arrow.up.forward.circle.fill" : "pause.circle", tint: coordinator.isRunning ? .green : .orange)
        }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Account Tracker", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.headline)
                Spacer()
                Text("750 GB daily cap per profile")
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
                ContentUnavailableView("No accounts tracked", systemImage: "gauge", description: Text("Refresh profiles to start tracking daily transfer usage."))
                    .frame(maxWidth: .infinity, minHeight: 120)
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

    private var selectedRemainingBytes: Int64 {
        coordinator.job.selectedRemoteNames.reduce(Int64(0)) { total, remoteName in
            total + coordinator.usage(for: remoteName).remainingBytes
        }
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
                            isAnyRunning: coordinator.isRunning,
                            onEdit: {
                                coordinator.selectJob(savedJob)
                            },
                            onRun: {
                                coordinator.runJob(savedJob)
                            },
                            onStop: {
                                coordinator.stop()
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
                    Text("Local folder")
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
                    Text("Remote path")
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
                ContentUnavailableView(
                    "No sync profile selected",
                    systemImage: "tray.full",
                    description: Text("Choose a saved sync profile above or click New to create one.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
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
        let remote = coordinator.firstSelectedRemoteName() ?? coordinator.remotes.first?.name ?? "profile:"
        let path = coordinator.job.remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? "\(remote) root" : "\(remote)\(path)"
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
                                Text(TransferStatsParser.formatBytes(coordinator.usage(for: remote.name).remainingBytes) + " left today")
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

            Text("Selected profiles form the failover pool, so SkyVault can continue with the next account when a profile reaches its daily upload limit.")
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
    let isAnyRunning: Bool
    let onEdit: () -> Void
    let onRun: () -> Void
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
                Label(job.remotePath.isEmpty ? "Remote root" : job.remotePath, systemImage: "cloud")
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
                Button(role: .destructive) {
                    onStop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
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

private struct ProfileEditorView: View {
    @EnvironmentObject private var coordinator: SyncCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SkyVault Profiles")
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
                Label("Resume reruns this sync job; rclone compares the destination and skips files already completed.", systemImage: "playpause")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
