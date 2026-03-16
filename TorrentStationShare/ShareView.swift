import SwiftUI

struct ShareView: View {
    let sharedURL: String
    let onDismiss: () -> Void

    @State private var url: String
    @State private var selectedDestination: String?
    @State private var selectedDestinationName: String?
    @State private var recentDestinations: [ShareRecentDestination] = []
    @State private var isSending = false
    @State private var resultMessage: String?
    @State private var isError = false
    @State private var isLoggedIn = false

    init(sharedURL: String, onDismiss: @escaping () -> Void) {
        self.sharedURL = sharedURL
        self.onDismiss = onDismiss
        _url = State(initialValue: sharedURL)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !isLoggedIn {
                    // Not logged in state
                    ContentUnavailableView(
                        "Not Connected",
                        systemImage: "externaldrive.trianglebadge.exclamationmark",
                        description: Text("Open TorrentStation and log in to your NAS first.")
                    )
                } else if let message = resultMessage {
                    // Result state
                    ContentUnavailableView(
                        isError ? "Failed" : "Sent!",
                        systemImage: isError ? "xmark.circle" : "checkmark.circle",
                        description: Text(message)
                    )
                    .foregroundStyle(isError ? .red : .green)
                } else {
                    // Main form
                    Form {
                        Section("URL") {
                            TextField("URL or magnet link", text: $url)
                                .font(.callout)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        Section("Destination") {
                            // Recent destinations from shared UserDefaults
                            Button {
                                selectedDestination = nil
                                selectedDestinationName = nil
                            } label: {
                                HStack {
                                    Text("Default")
                                    Spacer()
                                    if selectedDestination == nil {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color(red: 0, green: 0.83, blue: 0.67))
                                    }
                                }
                            }
                            .foregroundStyle(.primary)

                            ForEach(recentDestinations) { dest in
                                Button {
                                    selectedDestination = dest.path
                                    selectedDestinationName = dest.name
                                } label: {
                                    HStack {
                                        Image(systemName: "clock")
                                            .foregroundStyle(.secondary)
                                        Text(dest.name)
                                        Spacer()
                                        if selectedDestination == dest.path {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Color(red: 0, green: 0.83, blue: 0.67))
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Send to NAS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                if isLoggedIn && resultMessage == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSending {
                            ProgressView()
                        } else {
                            Button("Send") {
                                Task { await sendToNAS() }
                            }
                            .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                if resultMessage != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onDismiss() }
                    }
                }
            }
            .task {
                loadState()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - State Loading

    private func loadState() {
        // Check if user is logged in by loading credentials from shared Keychain
        if let _ = ShareCredentialsHelper.loadCredentials() {
            isLoggedIn = true
        }

        // Load recent destinations from shared UserDefaults
        if let defaults = UserDefaults(suiteName: ShareConstants.appGroupID),
           let data = defaults.data(forKey: "recentDestinations"),
           let decoded = try? JSONDecoder().decode([ShareRecentDestination].self, from: data) {
            recentDestinations = decoded
            // Pre-select the most recently used destination
            if let first = decoded.first {
                selectedDestination = first.path
                selectedDestinationName = first.name
            }
        }
    }

    // MARK: - Send to NAS

    private func sendToNAS() async {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        isSending = true

        do {
            try await ShareNASClient.createDownload(
                uri: trimmedURL,
                destination: selectedDestination
            )
            resultMessage = "Download started on NAS"
            isError = false
        } catch {
            resultMessage = error.localizedDescription
            isError = true
        }

        isSending = false
    }
}

// MARK: - Shared Models (lightweight duplicates for the extension)

struct ShareRecentDestination: Codable, Identifiable {
    let path: String
    let name: String
    var id: String { path }
}
