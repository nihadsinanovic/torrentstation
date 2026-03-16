import SwiftUI
import UserNotifications

@main
struct TorrentStationApp: App {
    @State private var authViewModel: AuthViewModel
    @State private var taskListViewModel: TaskListViewModel
    @State private var addTaskViewModel: AddTaskViewModel
    @State private var plexViewModel: PlexViewModel
    @State private var nasInfoViewModel: NASInfoViewModel
    @State private var selectedTab = 0

    init() {
        let client = SynologyClient()
        let authService = AuthService(client: client)
        let dsService = DownloadStationService(client: client)
        let fsService = FileStationService(client: client)
        let dsmService = DSMInfoService(client: client)
        let plexService = PlexService()

        _authViewModel = State(initialValue: AuthViewModel(authService: authService))
        _taskListViewModel = State(initialValue: TaskListViewModel(dsService: dsService, fsService: fsService))
        _addTaskViewModel = State(initialValue: AddTaskViewModel(dsService: dsService, fsService: fsService))
        _plexViewModel = State(initialValue: PlexViewModel(plexService: plexService))
        _nasInfoViewModel = State(initialValue: NASInfoViewModel(dsmService: dsmService))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                authViewModel: authViewModel,
                taskListViewModel: taskListViewModel,
                addTaskViewModel: addTaskViewModel,
                plexViewModel: plexViewModel,
                nasInfoViewModel: nasInfoViewModel,
                selectedTab: $selectedTab
            )
            .preferredColorScheme(.dark)
            .task {
                let center = UNUserNotificationCenter.current()
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            .onOpenURL { url in
                if url.scheme == "magnet" {
                    addTaskViewModel.setMagnetLink(url)
                    selectedTab = 1 // Switch to Add tab
                }
            }
            .onChange(of: addTaskViewModel.didStartDownload) {
                if addTaskViewModel.didStartDownload {
                    addTaskViewModel.didStartDownload = false
                    taskListViewModel.selectedFilter = .downloading
                    selectedTab = 0 // Switch to Downloads tab
                    Task { await taskListViewModel.refresh() }
                }
            }
        }
    }
}
