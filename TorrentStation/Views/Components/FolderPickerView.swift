import SwiftUI

struct FolderPickerView: View {
    let fsService: FileStationService
    let recentDestinations: [RecentDestination]
    let onSelect: (String?, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var sharedFolders: [ShareItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                // Recent destinations
                if !recentDestinations.isEmpty {
                    Section("Recent") {
                        ForEach(recentDestinations) { recent in
                            Button {
                                onSelect(recent.path, recent.name)
                                dismiss()
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recent.name)
                                        Text(recent.path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "clock.arrow.circlepath")
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                // Shared folders
                Section("Shared Folders") {
                    if isLoading {
                        ProgressView("Loading folders\u{2026}")
                    } else if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    } else {
                        ForEach(sharedFolders, id: \.path) { folder in
                            NavigationLink(value: FolderNavItem(path: folder.path, name: folder.name)) {
                                Label(folder.name, systemImage: "folder.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Destination")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FolderNavItem.self) { item in
                SubfolderListView(
                    folderPath: item.path,
                    folderName: item.name,
                    fsService: fsService,
                    onSelect: { path, name in
                        onSelect(path, name)
                        dismiss()
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await loadSharedFolders()
            }
        }
    }

    private func loadSharedFolders() async {
        isLoading = true
        errorMessage = nil
        do {
            sharedFolders = try await fsService.listSharedFolders()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Navigation Item

struct FolderNavItem: Hashable {
    let path: String
    let name: String
}

// MARK: - Subfolder List

struct SubfolderListView: View {
    let folderPath: String
    let folderName: String
    let fsService: FileStationService
    let onSelect: (String, String) -> Void

    @State private var subfolders: [FileItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            // Select this folder
            Button {
                // Strip /volume1/ prefix for Synology DownloadStation destination format
                let destination = destinationPath(from: folderPath)
                print("[FolderPicker] Selected path: '\(folderPath)' -> destination: '\(destination)'")
                onSelect(destination, folderName)
            } label: {
                Label("Select \"\(folderName)\"", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            }

            // Subfolders
            if isLoading {
                ProgressView("Loading\u{2026}")
            } else if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
            } else if subfolders.isEmpty {
                Text("No subfolders")
                    .foregroundStyle(.secondary)
            } else {
                Section("Subfolders") {
                    ForEach(subfolders) { folder in
                        NavigationLink(value: FolderNavItem(path: folder.path, name: folder.name)) {
                            Label(folder.name, systemImage: "folder")
                        }
                    }
                }
            }
        }
        .navigationTitle(folderName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: FolderNavItem.self) { item in
            SubfolderListView(
                folderPath: item.path,
                folderName: item.name,
                fsService: fsService,
                onSelect: onSelect
            )
        }
        .task {
            await loadSubfolders()
        }
    }

    private func loadSubfolders() async {
        isLoading = true
        errorMessage = nil
        do {
            let files = try await fsService.listFiles(folderPath: folderPath)
            subfolders = files.filter { $0.isdir }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Convert FileStation absolute path to DownloadStation destination format.
    /// FileStation returns paths in different formats:
    ///   - Shared folders: `/volume1/Shared` → strip `/volumeN/`
    ///   - Subfolder items: `/Shared/Videos/Movies` → strip leading `/`
    /// DownloadStation expects `Shared/Videos/Movies` (no leading slash, no volume prefix).
    private func destinationPath(from fullPath: String) -> String {
        var result = fullPath
        // Strip /volumeN/ prefix if present
        let pattern = #"^/volume\d+/"#
        result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        // Strip any remaining leading slash
        while result.hasPrefix("/") {
            result = String(result.dropFirst())
        }
        return result
    }
}
