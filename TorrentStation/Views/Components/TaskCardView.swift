import SwiftUI

struct TaskCardView: View {
    let task: DownloadTask
    let isSelecting: Bool
    let isSelected: Bool
    let onPause: () -> Void
    let onResume: () -> Void
    let onDelete: () -> Void
    let onToggleSelection: () -> Void
    var onPlay: (() -> Void)?

    // Plex integration (optional)
    var plexStatus: PlexMediaStatus?
    var onPlexScan: (() -> Void)?
    var onPlexPlay: (() -> Void)?

    private var isFoundInPlex: Bool {
        if case .found = plexStatus {
            return true
        }
        return false
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Title + Status Badge + Plex icon
                HStack {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(2)

                    Spacer()

                    if isFoundInPlex {
                        Image(systemName: "play.tv")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text(task.status.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.2), in: Capsule())
                        .foregroundStyle(statusColor)
                }

                // Progress Bar + Percentage
                HStack {
                    ProgressBarView(progress: task.progress, status: task.status)
                    Text(Formatters.formatProgress(task.progress))
                        .font(Theme.monoCaption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }

                // Speeds + Sizes
                HStack {
                    if task.downloadSpeed > 0 {
                        Label(Formatters.formatSpeed(task.downloadSpeed), systemImage: "arrow.down")
                            .font(Theme.monoCaption)
                            .foregroundStyle(Theme.downloading)
                    }

                    if task.uploadSpeed > 0 {
                        Label(Formatters.formatSpeed(task.uploadSpeed), systemImage: "arrow.up")
                            .font(Theme.monoCaption)
                            .foregroundStyle(Theme.seeding)
                    }

                    Spacer()

                    Text("\(Formatters.formatBytes(task.downloadedSize)) / \(Formatters.formatBytes(task.totalSize))")
                        .font(Theme.monoCaption)
                        .foregroundStyle(.secondary)
                }

            }
        }
        .padding(Theme.paddingMedium)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(.ultraThinMaterial)
        )
        .contentShape(Rectangle())
        .contextMenu {
            if !isSelecting {
                if task.canStream, let onPlay {
                    Button { onPlay() } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                }

                // Plex options (for finished/seeding/paused tasks when Plex is configured)
                if (task.status == .finished || task.status == .seeding || task.status == .paused), let status = plexStatus {
                    Divider()
                    switch status {
                    case .unknown, .checking:
                        Label("Checking Plex\u{2026}", systemImage: "hourglass")
                            .disabled(true)
                    case .found:
                        if let onPlexPlay {
                            Button { onPlexPlay() } label: {
                                Label("Play on Plex", systemImage: "play.tv")
                            }
                        }
                        if let onPlexScan {
                            Button { onPlexScan() } label: {
                                Label("Rescan in Plex", systemImage: "arrow.clockwise")
                            }
                        }
                    case .notFound:
                        if let onPlexScan {
                            Button { onPlexScan() } label: {
                                Label("Scan in Plex", systemImage: "arrow.clockwise")
                            }
                        }
                    case .scanning:
                        Label("Scanning\u{2026}", systemImage: "hourglass")
                            .disabled(true)
                    case .outsideLibrary(let dest, let libs):
                        Label("Not in a Plex library folder", systemImage: "exclamationmark.folder")
                            .disabled(true)
                        Text("Downloaded to: \(dest)")
                            .font(.caption)
                            .disabled(true)
                        if let first = libs.first {
                            Text("Plex watches: \(first)")
                                .font(.caption)
                                .disabled(true)
                        }
                        if let onPlexScan {
                            Button { onPlexScan() } label: {
                                Label("Rescan in Plex", systemImage: "arrow.clockwise")
                            }
                        }
                    case .error:
                        if let onPlexScan {
                            Button { onPlexScan() } label: {
                                Label("Retry Plex Scan", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }

                if task.status == .paused {
                    Button { onResume() } label: {
                        Label("Resume", systemImage: "play.circle")
                    }
                } else if task.status == .downloading || task.status == .waiting || task.status == .seeding {
                    Button { onPause() } label: {
                        Label("Pause", systemImage: "pause.circle")
                    }
                }

                Divider()

                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if !isSelecting {
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if !isSelecting {
                if task.status == .paused {
                    Button { onResume() } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .tint(Theme.downloading)
                } else if task.status == .downloading || task.status == .waiting || task.status == .seeding {
                    Button { onPause() } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .tint(Theme.paused)
                }
            }
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
}
