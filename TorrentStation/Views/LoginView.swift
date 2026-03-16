import SwiftUI

struct LoginView: View {
    @Bindable var viewModel: AuthViewModel

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case address, port, username, password
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App Header
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.connected.to.line.below.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.accent)
                        .padding(.bottom, 8)

                    Text("SynoTorrent")
                        .font(.largeTitle.bold())

                    Text("Connect to your Synology NAS")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                // Connection Section
                VStack(spacing: 16) {
                    // Connection mode picker
                    Picker("Connection", selection: $viewModel.connectionMode) {
                        ForEach(ConnectionMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    GroupBox("Connection") {
                        VStack(spacing: 12) {
                            if viewModel.connectionMode == .quickConnect {
                                // QuickConnect mode
                                TextField("QuickConnect ID", text: $viewModel.quickConnectID)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .focused($focusedField, equals: .address)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .username }
                            } else {
                                // Manual address mode
                                HStack {
                                    TextField("NAS Address (IP or hostname)", text: $viewModel.address)
                                        .textContentType(.URL)
                                        .keyboardType(.URL)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .focused($focusedField, equals: .address)
                                        .submitLabel(.next)
                                        .onSubmit { focusedField = .port }

                                    Button {
                                        Task { await viewModel.scanNetwork() }
                                    } label: {
                                        if viewModel.isScanning {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "antenna.radiowaves.left.and.right")
                                        }
                                    }
                                    .disabled(viewModel.isScanning)
                                }

                                TextField("Port", text: $viewModel.port)
                                    .keyboardType(.numberPad)
                                    .focused($focusedField, equals: .port)

                                Toggle("Use HTTPS", isOn: $viewModel.useHTTPS)
                                    .onChange(of: viewModel.useHTTPS) { _, newValue in
                                        if viewModel.port == "5000" && newValue {
                                            viewModel.port = "5001"
                                        } else if viewModel.port == "5001" && !newValue {
                                            viewModel.port = "5000"
                                        }
                                    }
                            }
                        }
                    }

                    GroupBox("Credentials") {
                        VStack(spacing: 12) {
                            TextField("Username", text: $viewModel.username)
                                .textContentType(.username)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .username)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }

                            SecureField("Password", text: $viewModel.password)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { Task { await viewModel.login() } }
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)

                // Error Message
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }

                // Login Button
                Button {
                    Task { await viewModel.login() }
                } label: {
                    Group {
                        if viewModel.isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                if viewModel.isResolving {
                                    Text("Resolving...")
                                        .font(.headline)
                                }
                            }
                        } else {
                            Text("Connect")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, Theme.paddingLarge)
            .frame(maxWidth: 500)
        }
        .sheet(isPresented: $viewModel.showDevicePicker) {
            DevicePickerSheet(
                devices: viewModel.discoveredDevices,
                onSelect: { viewModel.selectDevice($0) }
            )
            .presentationDetents([.medium])
        }
    }
}

struct DevicePickerSheet: View {
    let devices: [DiscoveredDevice]
    let onSelect: (DiscoveredDevice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(devices) { device in
                Button {
                    onSelect(device)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: device.type == .synology
                              ? "externaldrive.connected.to.line.below.fill"
                              : "play.tv")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.displayName)
                                .font(.body)
                            Text("\(device.address):\(device.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Devices Found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let client = SynologyClient()
    let authService = AuthService(client: client)
    LoginView(viewModel: AuthViewModel(authService: authService))
        .preferredColorScheme(.dark)
}
