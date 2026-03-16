import SwiftUI
import Observation
import UserNotifications

@Observable
@MainActor
final class TaskListViewModel {
    // MARK: - State
    var tasks: [DownloadTask] = []
    var globalDownloadSpeed: Int64 = 0
    var globalUploadSpeed: Int64 = 0
    var selectedFilter: TaskFilter = .all
    var errorMessage: String?
    var isLoading = false

    // MARK: - Selection State
    var isSelecting = false
    var selectedTaskIDs: Set<String> = []

    var filteredTasks: [DownloadTask] {
        tasks.filter { selectedFilter.matches($0) }
    }

    var filterCounts: [TaskFilter: Int] {
        var counts: [TaskFilter: Int] = [:]
        for filter in TaskFilter.allCases {
            counts[filter] = tasks.filter { filter.matches($0) }.count
        }
        return counts
    }

    var selectedTasks: [DownloadTask] {
        tasks.filter { selectedTaskIDs.contains($0.id) }
    }

    var canPauseSelection: Bool {
        selectedTasks.contains { [.downloading, .waiting, .seeding, .hashChecking, .extracting, .fileHostingWaiting, .unknown].contains($0.status) }
    }

    var canResumeSelection: Bool {
        selectedTasks.contains { $0.status == .paused }
    }

    var hasSelection: Bool {
        !selectedTaskIDs.isEmpty
    }

    // MARK: - Media Playback
    var mediaTask: DownloadTask?

    private let dsService: DownloadStationService
    let fsService: FileStationService
    private var pollingTask: Task<Void, Never>?
    private var previousStatuses: [String: TaskStatus] = [:]

    init(dsService: DownloadStationService, fsService: FileStationService) {
        self.dsService = dsService
        self.fsService = fsService
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        do {
            async let tasksResult = dsService.listTasks()
            async let statsResult = dsService.getStatistics()
            let (newTasks, stats) = try await (tasksResult, statsResult)

            // Detect state transitions and send notifications
            if !previousStatuses.isEmpty {
                for task in newTasks {
                    let oldStatus = previousStatuses[task.id]
                    guard let oldStatus, oldStatus != task.status else { continue }

                    if task.status == .seeding && oldStatus != .seeding {
                        sendNotification(
                            title: "Now Seeding",
                            body: task.title
                        )
                    } else if task.status == .finished && oldStatus == .seeding {
                        sendNotification(
                            title: "Download Complete",
                            body: "\(task.title) — finished seeding"
                        )
                    } else if task.status == .finished && oldStatus != .finished {
                        sendNotification(
                            title: "Download Complete",
                            body: task.title
                        )
                    }
                }
            }

            // Update previous statuses
            previousStatuses = Dictionary(uniqueKeysWithValues: newTasks.map { ($0.id, $0.status) })

            self.tasks = newTasks
            self.globalDownloadSpeed = stats.speed_download
            self.globalUploadSpeed = stats.speed_upload
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Task Actions

    func pauseTask(_ task: DownloadTask) async {
        do {
            try await dsService.pauseTasks(ids: [task.id])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resumeTask(_ task: DownloadTask) async {
        do {
            try await dsService.resumeTasks(ids: [task.id])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTask(_ task: DownloadTask) async {
        do {
            try await dsService.deleteTasks(ids: [task.id])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Selection

    func toggleSelecting() {
        isSelecting.toggle()
        if !isSelecting {
            selectedTaskIDs.removeAll()
        }
    }

    func toggleSelection(for task: DownloadTask) {
        if selectedTaskIDs.contains(task.id) {
            selectedTaskIDs.remove(task.id)
        } else {
            selectedTaskIDs.insert(task.id)
        }
    }

    func selectAll() {
        for task in filteredTasks {
            selectedTaskIDs.insert(task.id)
        }
    }

    func deselectAll() {
        selectedTaskIDs.removeAll()
    }

    // MARK: - Batch Actions

    func pauseSelected() async {
        let ids = selectedTasks
            .filter { [.downloading, .waiting, .seeding, .hashChecking, .extracting, .fileHostingWaiting, .unknown].contains($0.status) }
            .map(\.id)
        guard !ids.isEmpty else { return }
        do {
            try await dsService.pauseTasks(ids: ids)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resumeSelected() async {
        let ids = selectedTasks
            .filter { $0.status == .paused }
            .map(\.id)
        guard !ids.isEmpty else { return }
        do {
            try await dsService.resumeTasks(ids: ids)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelected() async {
        let ids = Array(selectedTaskIDs)
        guard !ids.isEmpty else { return }
        do {
            try await dsService.deleteTasks(ids: ids)
            selectedTaskIDs.removeAll()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
