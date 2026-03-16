import SwiftUI
import AVKit

/// Formats natively playable by AVPlayer on iOS
private let avPlayerExtensions: Set<String> = ["mp4", "mov", "m4v", "m4a", "mp3", "wav", "aiff"]

struct MediaPlayerView: View {
    let title: String
    let streamURL: URL
    let fileName: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var showingShareSheet = false

    private var isNativelyPlayable: Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return avPlayerExtensions.contains(ext)
    }

    var body: some View {
        Group {
            if isNativelyPlayable {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { startNativePlayback() }
                    .onDisappear {
                        player?.pause()
                        player = nil
                    }
            } else {
                // Non-native format (MKV, AVI, etc.) — offer external playback
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "film")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        Text(fileName)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)

                        let ext = (fileName as NSString).pathExtension.uppercased()
                        Text("\(ext) files require an external player (VLC, Infuse, etc.)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        // Open in VLC directly if installed
                        Button {
                            openInVLC()
                        } label: {
                            Label("Open in VLC", systemImage: "play.rectangle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)

                        // Open via share sheet for other apps
                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("Open in Other App...", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        // Open in Safari as a fallback
                        Button {
                            UIApplication.shared.open(streamURL)
                        } label: {
                            Label("Open in Safari", systemImage: "safari")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                }
                .sheet(isPresented: $showingShareSheet) {
                    ShareSheet(items: [streamURL])
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startNativePlayback() {
        let playerItem = AVPlayerItem(url: streamURL)
        let avPlayer = AVPlayer(playerItem: playerItem)
        self.player = avPlayer
        avPlayer.play()
    }

    private func openInVLC() {
        // VLC URL scheme: vlc-x-callback://x-callback-url/stream?url=<encoded-url>
        let encodedURL = streamURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? streamURL.absoluteString
        if let vlcURL = URL(string: "vlc-x-callback://x-callback-url/stream?url=\(encodedURL)") {
            if UIApplication.shared.canOpenURL(vlcURL) {
                UIApplication.shared.open(vlcURL)
            } else {
                // VLC not installed — open App Store page
                if let appStoreURL = URL(string: "https://apps.apple.com/app/vlc-media-player/id650377962") {
                    UIApplication.shared.open(appStoreURL)
                }
            }
        }
    }
}

/// UIKit share sheet wrapper for SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// A view that handles loading media files from a task's destination folder,
/// then presenting the player once a streaming URL is ready.
struct MediaLoadingView: View {
    let task: DownloadTask
    let fileStationService: FileStationService
    @Environment(\.dismiss) private var dismiss

    @State private var streamURL: URL?
    @State private var mediaFiles: [FileItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedFile: FileItem?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Finding media files...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    }
                } else if let streamURL {
                    MediaPlayerView(
                        title: selectedFile?.name ?? task.title,
                        streamURL: streamURL,
                        fileName: selectedFile?.name ?? task.title
                    )
                } else if !mediaFiles.isEmpty {
                    // Multiple media files — let user pick
                    List(mediaFiles) { file in
                        Button {
                            Task { await selectFile(file) }
                        } label: {
                            HStack {
                                Image(systemName: file.isVideo ? "film" : "music.note")
                                    .foregroundStyle(Theme.accent)

                                VStack(alignment: .leading) {
                                    Text(file.name)
                                        .font(.body)
                                        .lineLimit(2)
                                    if let size = file.additional?.size {
                                        Text(Formatters.formatBytes(size))
                                            .font(Theme.monoCaption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Theme.accent)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .navigationTitle("Media Files")
                } else {
                    ContentUnavailableView {
                        Label("No Media", systemImage: "film")
                    } description: {
                        Text("No playable media files found in this download.")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadMediaFiles()
            }
        }
    }

    private func loadMediaFiles() async {
        guard let destination = task.destination else {
            errorMessage = "Download destination unknown"
            isLoading = false
            return
        }

        let titleIsFile = MediaHelper.isMediaFile(task.title)

        if titleIsFile {
            // Single-file torrent — the file is directly in the destination folder
            let result = await fileStationService.streamingURLWithFallback(
                destination: destination,
                fileName: task.title
            )
            if let url = result.url {
                streamURL = url
            } else {
                errorMessage = "Could not build streaming URL for:\n\(result.resolvedPath)"
            }
            isLoading = false
            return
        }

        // Folder torrent — search inside the folder for media files
        do {
            let result = try await fileStationService.findMediaFilesWithFallback(
                destination: destination,
                title: task.title
            )
            mediaFiles = result.files

            if result.files.count == 1 {
                await selectFile(result.files[0])
            } else if result.files.isEmpty {
                errorMessage = "No media files found in:\n\(result.resolvedPath)"
            }
        } catch {
            errorMessage = "Could not find media files.\n\n\(error.localizedDescription)\n\nDestination: \(destination)"
        }
        isLoading = false
    }

    private func selectFile(_ file: FileItem) async {
        selectedFile = file
        streamURL = await fileStationService.streamingURL(for: file.path)
        if streamURL == nil {
            errorMessage = "Could not build streaming URL"
        }
    }
}
