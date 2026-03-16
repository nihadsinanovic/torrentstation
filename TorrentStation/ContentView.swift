import SwiftUI

struct ContentView: View {
    var authViewModel: AuthViewModel
    var taskListViewModel: TaskListViewModel
    var addTaskViewModel: AddTaskViewModel
    var plexViewModel: PlexViewModel
    var nasInfoViewModel: NASInfoViewModel
    @Binding var selectedTab: Int

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                MainTabView(
                    authViewModel: authViewModel,
                    taskListViewModel: taskListViewModel,
                    addTaskViewModel: addTaskViewModel,
                    plexViewModel: plexViewModel,
                    nasInfoViewModel: nasInfoViewModel,
                    selectedTab: $selectedTab
                )
            } else {
                LoginView(viewModel: authViewModel)
            }
        }
        .animation(.default, value: authViewModel.isAuthenticated)
        .task {
            await authViewModel.attemptAutoLogin()
        }
        .task {
            await plexViewModel.loadConfig()
        }
        .onChange(of: authViewModel.isAuthenticated) {
            if authViewModel.isAuthenticated {
                plexViewModel.prefillAddress(authViewModel.connectedAddress)
                Task { await nasInfoViewModel.loadDeviceInfo() }
            }
        }
    }
}

struct MainTabView: View {
    var authViewModel: AuthViewModel
    var taskListViewModel: TaskListViewModel
    var addTaskViewModel: AddTaskViewModel
    var plexViewModel: PlexViewModel
    var nasInfoViewModel: NASInfoViewModel
    @Binding var selectedTab: Int

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Downloads", systemImage: "arrow.down.circle.fill", value: 0) {
                TaskListView(viewModel: taskListViewModel, plexViewModel: plexViewModel)
            }

            Tab("Add", systemImage: "plus.circle.fill", value: 1) {
                AddTaskView(viewModel: addTaskViewModel)
            }

            Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                SettingsView(
                    connectedAddress: authViewModel.connectedAddress,
                    connectedUsername: authViewModel.connectedUsername,
                    plexViewModel: plexViewModel,
                    nasInfoViewModel: nasInfoViewModel,
                    onLogout: { await authViewModel.logout() }
                )
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.accent)
    }
}
