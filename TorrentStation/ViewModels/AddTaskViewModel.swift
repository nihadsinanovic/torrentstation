import SwiftUI
import Observation

@Observable
@MainActor
final class AddTaskViewModel {
    var inputText: String = ""
    var isSubmitting = false
    var successMessage: String?
    var errorMessage: String?
    var didStartDownload = false

    // Destination selection
    var selectedDestination: String?
    var selectedDestinationName: String?
    var showFolderPicker = false

    // Recent destinations (max 3, most recent first)
    var recentDestinations: [RecentDestination] = []

    var canSubmit: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    private let dsService: DownloadStationService
    let fsService: FileStationService

    private static let recentDestinationsKey = "recentDestinations"
    private static let maxRecent = 3

    init(dsService: DownloadStationService, fsService: FileStationService) {
        self.dsService = dsService
        self.fsService = fsService
        loadRecentDestinations()
        // Pre-select the last used destination if the user has used one before
        if let last = recentDestinations.first {
            selectedDestination = last.path
            selectedDestinationName = last.name
        }
    }

    func submitTask() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        didStartDownload = false

        do {
            print("[AddTask] Submitting task with destination: '\(selectedDestination ?? "nil")'")
            try await dsService.createTask(uri: trimmed, destination: selectedDestination)

            // Save destination to recents
            if let dest = selectedDestination, let name = selectedDestinationName {
                addRecentDestination(path: dest, name: name)
            }

            successMessage = "Download started!"
            inputText = ""
            didStartDownload = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }

    /// Called when the app receives a magnet link via deep linking
    func setMagnetLink(_ url: URL) {
        // magnet: URLs arrive as-is — use absoluteString to preserve the full URI
        inputText = url.absoluteString
        errorMessage = nil
        successMessage = nil
    }

    // MARK: - Recent Destinations Persistence

    private func loadRecentDestinations() {
        let defaults = SharedConstants.sharedDefaults ?? UserDefaults.standard
        guard let data = defaults.data(forKey: Self.recentDestinationsKey),
              let decoded = try? JSONDecoder().decode([RecentDestination].self, from: data) else {
            return
        }
        recentDestinations = decoded
    }

    private func saveRecentDestinations() {
        let defaults = SharedConstants.sharedDefaults ?? UserDefaults.standard
        if let data = try? JSONEncoder().encode(recentDestinations) {
            defaults.set(data, forKey: Self.recentDestinationsKey)
        }
    }

    func addRecentDestination(path: String, name: String) {
        // Remove existing entry with same path
        recentDestinations.removeAll { $0.path == path }
        // Insert at the front
        recentDestinations.insert(RecentDestination(path: path, name: name), at: 0)
        // Cap at max
        if recentDestinations.count > Self.maxRecent {
            recentDestinations = Array(recentDestinations.prefix(Self.maxRecent))
        }
        saveRecentDestinations()
    }
}

struct RecentDestination: Codable, Equatable, Identifiable {
    let path: String
    let name: String

    var id: String { path }
}
