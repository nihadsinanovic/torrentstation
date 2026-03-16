import SwiftUI

struct TaskListView: View {
    @Bindable var viewModel: TaskListViewModel
    var plexViewModel: PlexViewModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                // Global Speed
                Section {
                    SpeedBadgeView(
                        downloadSpeed: viewModel.globalDownloadSpeed,
                        uploadSpeed: viewModel.globalUploadSpeed
                    )
                }

                // Filter Bar
                Section {
                    FilterChipBar(
                        selectedFilter: $viewModel.selectedFilter,
                        counts: viewModel.filterCounts
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // Task Cards
                Section {
                    if viewModel.filteredTasks.isEmpty {
                        ContentUnavailableView {
                            Label("No Torrents", systemImage: "tray")
                        } description: {
                            Text(viewModel.selectedFilter == .all
                                 ? "Add a torrent to get started"
                                 : "No \(viewModel.selectedFilter.displayName.lowercased()) torrents")
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(viewModel.filteredTasks) { task in
                            taskCard(for: task)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(
                                    top: 4, leading: 16, bottom: 4, trailing: 16
                                ))
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) {
                            viewModel.toggleSelecting()
                        }
                    } label: {
                        Text(viewModel.isSelecting ? "Done" : "Select")
                    }
                    .disabled(viewModel.tasks.isEmpty)
                }

                if viewModel.isSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if viewModel.selectedTaskIDs.count == viewModel.filteredTasks.count {
                                viewModel.deselectAll()
                            } else {
                                viewModel.selectAll()
                            }
                        } label: {
                            Text(viewModel.selectedTaskIDs.count == viewModel.filteredTasks.count
                                 ? "Deselect All" : "Select All")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if viewModel.isSelecting && viewModel.hasSelection {
                    batchActionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: viewModel.hasSelection)
            .animation(.snappy, value: viewModel.isSelecting)
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                viewModel.startPolling()
            }
            .onDisappear {
                viewModel.stopPolling()
            }
            .onChange(of: viewModel.tasks.map(\.id)) {
                Task { await plexViewModel.autoCheckTasks(viewModel.tasks) }
            }
            .onChange(of: viewModel.tasks.map(\.status)) {
                Task { await plexViewModel.autoCheckTasks(viewModel.tasks) }
            }
            .confirmationDialog(
                "Delete \(viewModel.selectedTaskIDs.count) torrent(s)?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.deleteSelected() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the selected torrents from Download Station.")
            }
            .sheet(item: $viewModel.mediaTask) { task in
                MediaLoadingView(
                    task: task,
                    fileStationService: viewModel.fsService
                )
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
    }

    @ViewBuilder
    private func taskCard(for task: DownloadTask) -> some View {
        let plexConfigured = plexViewModel.isConfigured
        let cardView = TaskCardView(
            task: task,
            isSelecting: viewModel.isSelecting,
            isSelected: viewModel.selectedTaskIDs.contains(task.id),
            onPause: { Task { await viewModel.pauseTask(task) } },
            onResume: { Task { await viewModel.resumeTask(task) } },
            onDelete: { Task { await viewModel.deleteTask(task) } },
            onToggleSelection: { viewModel.toggleSelection(for: task) },
            onPlay: task.canStream ? { viewModel.mediaTask = task } : nil,
            plexStatus: plexConfigured ? plexViewModel.plexStatus(for: task.id) : nil,
            onPlexScan: plexConfigured ? { Task { await plexViewModel.triggerScan(for: task) } } : nil,
            onPlexPlay: plexConfigured ? { Task { await plexViewModel.initiatePlayback(for: task) } } : nil
        )

        if viewModel.isSelecting {
            cardView
                .onTapGesture {
                    viewModel.toggleSelection(for: task)
                }
        } else {
            NavigationLink {
                TaskDetailView(
                    task: task,
                    fileStationService: viewModel.fsService,
                    plexViewModel: plexViewModel,
                    onPause: { await viewModel.pauseTask(task) },
                    onResume: { await viewModel.resumeTask(task) },
                    onDelete: { await viewModel.deleteTask(task) }
                )
            } label: {
                cardView
            }
            .buttonStyle(.plain)
        }
    }

    private var batchActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 20) {
                Text("\(viewModel.selectedTaskIDs.count) selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if viewModel.canResumeSelection {
                    Button {
                        Task { await viewModel.resumeSelected() }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                    }
                    .tint(Theme.accent)
                }

                if viewModel.canPauseSelection {
                    Button {
                        Task { await viewModel.pauseSelected() }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                    }
                    .tint(Theme.paused)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
            }
            .padding(.horizontal, Theme.paddingMedium)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
}
