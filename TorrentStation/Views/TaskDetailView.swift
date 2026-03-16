import SwiftUI

struct TaskDetailView: View {
    let task: DownloadTask
    let fileStationService: FileStationService
    var plexViewModel: PlexViewModel
    let onPause: () async -> Void
    let onResume: () async -> Void
    let onDelete: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var files: [FileItem] = []
    @State private var isLoadingFiles = true
    @State private var fileError: String?
    @State private var showDeleteConfirmation = false
    @State private var selectedMediaFile: FileItem?
    @State private var streamURL: URL?

    private var isFoundInPlex: Bool {
        if case .found = plexViewModel.plexStatus(for: task.id) {
            return true
        }
        return false
    }

    private var plexStatus: PlexMediaStatus {
        plexViewModel.plexStatus(for: task.id)
    }

    private var eta: String? {
        guard task.status == .downloading, task.downloadSpeed > 0 else { return nil }
        let remaining = task.totalSize - task.downloadedSize
        let seconds = remaining / task.downloadSpeed
        return Formatters.formatEta(seconds: seconds)
    }

    private var elapsedTime: String? {
        guard let createTime = task.createTime else { return nil }
        let interval = Date().timeIntervalSince(createTime)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private var averageSpeed: Int64? {
        guard let createTime = task.createTime, task.downloadedSize > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(createTime)
        guard elapsed > 0 else { return nil }
        return Int64(Double(task.downloadedSize) / elapsed)
    }

    private var ratio: Double? {
        guard task.downloadedSize > 0 else { return nil }
        return Double(task.uploadedSize) / Double(task.downloadedSize)
    }

    var body: some View {
        List {
            // MARK: - Status & Progress
            Section {
                statusRow
                progressSection
            }

            // MARK: - Transfer Stats
            Section("Transfer") {
                transferStats
            }

            // MARK: - Details
            Section("Details") {
                detailRows
            }

            // MARK: - Playback
            if task.isLikelyMedia && (task.status == .finished || task.status == .seeding || task.status == .paused) {
                Section("Playback") {
                    playbackSection
                }
            }

            // MARK: - Files
            Section("Files") {
                filesSection
            }

            // MARK: - Actions
            Section {
                actionsSection
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadFiles()
        }
        .confirmationDialog(
            "Delete this torrent?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await onDelete()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the torrent from Download Station.")
        }
        .sheet(item: $selectedMediaFile) { file in
            NavigationStack {
                if let streamURL {
                    MediaPlayerView(
                        title: file.name,
                        streamURL: streamURL,
                        fileName: file.name
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                selectedMediaFile = nil
                                self.streamURL = nil
                            }
                        }
                    }
                } else {
                    ProgressView("Loading stream...")
                }
            }
        }
        .sheet(isPresented: Bindable(plexViewModel).showClientPicker) {
            if let pending = plexViewModel.pendingPlaybackItem {
                PlexClientPickerView(
                    clients: plexViewModel.availableClients,
                    taskTitle: pending.taskTitle
                ) { client in
                    Task {
                        await plexViewModel.playOnClient(client, mediaKey: pending.mediaKey)
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .alert(
            "Plex Playback Error",
            isPresented: Binding(
                get: { plexViewModel.playbackError != nil },
                set: { if !$0 { plexViewModel.playbackError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(plexViewModel.playbackError ?? "")
        }
    }

    // MARK: - Status Row

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            Text(task.title)
                .font(.headline)
                .lineLimit(3)

            Spacer()

            if isFoundInPlex {
                Image(systemName: "play.tv")
                    .font(.body)
                    .foregroundStyle(.orange)
            }
        }

        HStack {
            Text(task.status.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)

            Spacer()

            Text(Formatters.formatProgress(task.progress))
                .font(Theme.monoBody)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        ProgressBarView(progress: task.progress, status: task.status)
            .frame(height: 8)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
    }

    // MARK: - Transfer Stats

    @ViewBuilder
    private var transferStats: some View {
        if task.downloadSpeed > 0 || task.status == .downloading {
            statRow(
                icon: "arrow.down",
                label: "Download Speed",
                value: Formatters.formatSpeed(task.downloadSpeed),
                color: Theme.downloading
            )
        }

        if task.uploadSpeed > 0 || task.status == .seeding {
            statRow(
                icon: "arrow.up",
                label: "Upload Speed",
                value: Formatters.formatSpeed(task.uploadSpeed),
                color: Theme.seeding
            )
        }

        statRow(
            icon: "arrow.down.to.line",
            label: "Downloaded",
            value: "\(Formatters.formatBytes(task.downloadedSize)) / \(Formatters.formatBytes(task.totalSize))"
        )

        if task.uploadedSize > 0 {
            statRow(
                icon: "arrow.up.to.line",
                label: "Uploaded",
                value: Formatters.formatBytes(task.uploadedSize)
            )
        }

        if let ratio {
            statRow(
                icon: "arrow.up.arrow.down",
                label: "Ratio",
                value: String(format: "%.2f", ratio)
            )
        }

        if let eta {
            statRow(
                icon: "clock",
                label: "ETA",
                value: eta
            )
        }

        if let averageSpeed {
            statRow(
                icon: "gauge.with.dots.needle.50percent",
                label: "Average Speed",
                value: Formatters.formatSpeed(averageSpeed)
            )
        }
    }

    // MARK: - Detail Rows

    @ViewBuilder
    private var detailRows: some View {
        if let createTime = task.createTime {
            statRow(
                icon: "calendar",
                label: "Added",
                value: createTime.formatted(date: .abbreviated, time: .shortened)
            )
        }

        if let elapsedTime {
            statRow(
                icon: "timer",
                label: "Elapsed",
                value: elapsedTime
            )
        }

        if let destination = task.destination {
            statRow(
                icon: "folder",
                label: "Destination",
                value: destination
            )
        }

        statRow(
            icon: "doc",
            label: "Size",
            value: Formatters.formatBytes(task.totalSize)
        )
    }

    // MARK: - Playback Section

    @ViewBuilder
    private var playbackSection: some View {
        // Plex playback
        if plexViewModel.isConfigured {
            switch plexStatus {
            case .found:
                Button {
                    Task { await plexViewModel.initiatePlayback(for: task) }
                } label: {
                    Label("Play on Plex", systemImage: "play.tv")
                }
                .tint(.orange)

            case .checking:
                Label("Checking Plex...", systemImage: "hourglass")
                    .foregroundStyle(.secondary)

            case .scanning:
                Label("Scanning Plex...", systemImage: "hourglass")
                    .foregroundStyle(.secondary)

            case .notFound:
                Button {
                    Task { await plexViewModel.triggerScan(for: task) }
                } label: {
                    Label("Scan in Plex", systemImage: "arrow.clockwise")
                }

            case .outsideLibrary(let dest, let libs):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Not in a Plex library folder", systemImage: "exclamationmark.folder")
                        .foregroundStyle(.orange)
                    Text("Downloaded to: \(dest)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let first = libs.first {
                        Text("Plex watches: \(first)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await plexViewModel.triggerScan(for: task) }
                } label: {
                    Label("Rescan in Plex", systemImage: "arrow.clockwise")
                }

            case .error(let msg):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Plex Error", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await plexViewModel.triggerScan(for: task) }
                } label: {
                    Label("Retry Scan", systemImage: "arrow.clockwise")
                }

            case .unknown:
                Button {
                    Task { await plexViewModel.checkPlexStatus(for: task) }
                } label: {
                    Label("Check in Plex", systemImage: "magnifyingglass")
                }
            }
        }

        // On-device playback
        let mediaFilesList = files.filter { $0.isMedia }
        if !mediaFilesList.isEmpty {
            ForEach(mediaFilesList) { file in
                Button {
                    Task { await playFile(file) }
                } label: {
                    HStack {
                        Image(systemName: file.isVideo ? "film" : "music.note")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading) {
                            Text(file.name)
                                .font(.subheadline)
                                .lineLimit(2)
                            if let size = file.additional?.size {
                                Text(Formatters.formatBytes(size))
                                    .font(Theme.monoCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        } else if !isLoadingFiles && !plexViewModel.isConfigured {
            Text("No playable media files found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Files Section

    @ViewBuilder
    private var filesSection: some View {
        if isLoadingFiles {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading files...")
                    .foregroundStyle(.secondary)
            }
        } else if let fileError {
            Label(fileError, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if files.isEmpty {
            Text("No files found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(files) { file in
                HStack {
                    Image(systemName: iconForFile(file))
                        .foregroundStyle(file.isMedia ? Theme.accent : .secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .font(.subheadline)
                            .lineLimit(2)
                        if let size = file.additional?.size {
                            Text(Formatters.formatBytes(size))
                                .font(Theme.monoCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        if task.status == .paused {
            Button {
                Task { await onResume() }
            } label: {
                Label("Resume", systemImage: "play.circle")
            }
            .tint(Theme.accent)
        } else if task.status == .downloading || task.status == .waiting || task.status == .seeding {
            Button {
                Task { await onPause() }
            } label: {
                Label("Pause", systemImage: "pause.circle")
            }
            .tint(Theme.paused)
        }

        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private func statRow(icon: String, label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Theme.monoCaption)
        }
    }

    private func iconForFile(_ file: FileItem) -> String {
        if file.isdir { return "folder.fill" }
        if file.isVideo { return "film" }
        if file.isMedia { return "music.note" }
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "srt", "sub", "ass", "ssa", "vtt":
            return "captions.bubble"
        case "nfo", "txt":
            return "doc.text"
        case "jpg", "jpeg", "png", "gif", "webp":
            return "photo"
        default:
            return "doc"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .downloading, .hashChecking, .extracting, .fileHostingWaiting, .waiting, .unknown:
            Theme.downloading
        case .seeding: Theme.seeding
        case .paused: Theme.paused
        case .finished: Theme.completed
        case .error: Theme.error
        }
    }

    private func loadFiles() async {
        guard let destination = task.destination else {
            isLoadingFiles = false
            fileError = "Destination unknown"
            return
        }

        let titleIsFile = MediaHelper.isMediaFile(task.title)
        if titleIsFile {
            // Single file torrent — try to list the parent folder
            do {
                let resolvedDest = await fileStationService.resolveDestinationPath(destination)
                let parentFiles = try await fileStationService.listFiles(folderPath: resolvedDest)
                // Find our file
                files = parentFiles.filter { $0.name == task.title }
            } catch {
                fileError = "Could not list files"
            }
            isLoadingFiles = false
            return
        }

        // Folder torrent — list all files inside
        do {
            let result = try await fileStationService.findMediaFilesWithFallback(
                destination: destination,
                title: task.title
            )
            // Get all files (not just media) from the resolved path
            let folderPath = result.resolvedPath.isEmpty ? await fileStationService.resolveDestinationPath(destination) + "/" + task.title : result.resolvedPath
            // Actually, get all files from the torrent folder
            let allFiles = try await fileStationService.listFiles(folderPath: folderPath)
            files = allFiles.sorted { file1, file2 in
                // Media files first, then by size
                if file1.isMedia != file2.isMedia { return file1.isMedia }
                return (file1.additional?.size ?? 0) > (file2.additional?.size ?? 0)
            }
        } catch {
            // Fallback: try direct path resolution
            do {
                let resolvedDest = await fileStationService.resolveDestinationPath(destination)
                let folderPath = "\(resolvedDest)/\(task.title)"
                let allFiles = try await fileStationService.listFiles(folderPath: folderPath)
                files = allFiles.sorted { file1, file2 in
                    if file1.isMedia != file2.isMedia { return file1.isMedia }
                    return (file1.additional?.size ?? 0) > (file2.additional?.size ?? 0)
                }
            } catch {
                fileError = "Could not list files"
            }
        }
        isLoadingFiles = false
    }

    private func playFile(_ file: FileItem) async {
        streamURL = await fileStationService.streamingURL(for: file.path)
        if streamURL != nil {
            selectedMediaFile = file
        }
    }
}
