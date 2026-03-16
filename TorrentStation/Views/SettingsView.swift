import SwiftUI

struct SettingsView: View {
    let connectedAddress: String
    let connectedUsername: String
    var plexViewModel: PlexViewModel
    var nasInfoViewModel: NASInfoViewModel
    let onLogout: () async -> Void

    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    NavigationLink {
                        NASDetailView(viewModel: nasInfoViewModel)
                    } label: {
                        HStack {
                            Image(systemName: "externaldrive.connected.to.line.below.fill")
                                .foregroundStyle(Theme.accent)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(nasInfoViewModel.modelName ?? "Synology NAS")
                                    .font(.body.weight(.medium))
                                Text(connectedAddress)
                                    .font(Theme.monoCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    LabeledContent("Username") {
                        Text(connectedUsername)
                            .font(Theme.monoCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                PlexSettingsSection(plexViewModel: plexViewModel)

                Section("App Info") {
                    LabeledContent("App Name", value: "SynoTorrent")
                    LabeledContent("Version", value: "1.0.0")
                }

                Section {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        Label("Disconnect", systemImage: "power")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Disconnect from NAS?",
                isPresented: $showLogoutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    Task { await onLogout() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You will need to log in again to manage downloads.")
            }
        }
    }
}
