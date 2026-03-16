import SwiftUI

struct PlexSettingsSection: View {
    @Bindable var plexViewModel: PlexViewModel

    var body: some View {
        Section("Plex Media Server") {
            if plexViewModel.isConfigured {
                LabeledContent("Server") {
                    Text("\(plexViewModel.serverAddress):\(plexViewModel.port)")
                        .font(Theme.monoCaption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Status") {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.completed)
                }

                Button(role: .destructive) {
                    Task { await plexViewModel.disconnectPlex() }
                } label: {
                    Label("Disconnect Plex", systemImage: "xmark.circle")
                }
            } else {
                HStack {
                    TextField("Server Address", text: $plexViewModel.serverAddress)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        Task { await plexViewModel.scanForPlexServers() }
                    } label: {
                        if plexViewModel.isScanningNetwork {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .disabled(plexViewModel.isScanningNetwork)
                }

                TextField("Port", text: $plexViewModel.port)
                    .keyboardType(.numberPad)

                Toggle("Use HTTPS", isOn: $plexViewModel.useHTTPS)

                // Sign in or show token status
                if plexViewModel.token.isEmpty {
                    Button {
                        Task { await plexViewModel.signInWithPlex() }
                    } label: {
                        HStack {
                            if plexViewModel.isSigningIn {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Waiting for sign-in\u{2026}")
                                    .font(.subheadline)
                            } else {
                                Label("Sign in with Plex", systemImage: "person.badge.key")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(plexViewModel.isSigningIn)
                } else {
                    LabeledContent("Account") {
                        Label("Signed in", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.completed)
                    }

                    HStack {
                        Button {
                            Task { await plexViewModel.testConnection() }
                        } label: {
                            if plexViewModel.isTestingConnection {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Test", systemImage: "network")
                            }
                        }
                        .disabled(plexViewModel.serverAddress.isEmpty)

                        Spacer()

                        Button {
                            Task { await plexViewModel.saveConfig() }
                        } label: {
                            if plexViewModel.isSaving {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Save")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(plexViewModel.serverAddress.isEmpty)
                    }
                }

                if let result = plexViewModel.connectionTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("Connected") ? Theme.completed : Theme.error)
                }

                if let error = plexViewModel.signInError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                }

                if let error = plexViewModel.settingsError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                }
            }
        }
        .sheet(isPresented: Bindable(plexViewModel).showPlexDevicePicker) {
            DevicePickerSheet(
                devices: plexViewModel.discoveredPlexServers,
                onSelect: { plexViewModel.selectPlexServer($0) }
            )
            .presentationDetents([.medium])
        }
    }
}
