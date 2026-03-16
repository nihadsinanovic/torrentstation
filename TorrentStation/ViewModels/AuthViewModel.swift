import SwiftUI
import Observation

enum ConnectionMode: String, CaseIterable {
    case address = "Address"
    case quickConnect = "QuickConnect"
}

@Observable
@MainActor
final class AuthViewModel {
    // MARK: - Form State
    var connectionMode: ConnectionMode = .address
    var address: String = ""
    var port: String = "5000"
    var username: String = ""
    var password: String = ""
    var useHTTPS: Bool = false
    var quickConnectID: String = ""

    // MARK: - Auth State
    var isAuthenticated = false
    var isLoading = false
    var isResolving = false
    var errorMessage: String?

    // Displayed in Settings
    var connectedAddress: String = ""
    var connectedUsername: String = ""

    // MARK: - Network Scanning
    var isScanning = false
    var discoveredDevices: [DiscoveredDevice] = []
    var showDevicePicker = false

    private let authService: AuthService
    private let networkScanner = NetworkScannerService()

    init(authService: AuthService) {
        self.authService = authService
    }

    // MARK: - Actions

    func login() async {
        if connectionMode == .quickConnect {
            await loginWithQuickConnect()
        } else {
            await loginWithAddress()
        }
    }

    private func loginWithAddress() async {
        guard !address.isEmpty, !username.isEmpty, !password.isEmpty else {
            errorMessage = "All fields are required"
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let config = ConnectionConfig(
                address: address,
                port: Int(port) ?? (useHTTPS ? 5001 : 5000),
                useHTTPS: useHTTPS
            )
            _ = try await authService.login(
                config: config,
                username: username,
                password: password
            )
            connectedAddress = config.baseURL
            connectedUsername = username
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loginWithQuickConnect() async {
        guard !quickConnectID.isEmpty, !username.isEmpty, !password.isEmpty else {
            errorMessage = "All fields are required"
            return
        }
        isLoading = true
        isResolving = true
        errorMessage = nil
        do {
            let (_, config) = try await authService.loginWithQuickConnect(
                quickConnectID: quickConnectID,
                username: username,
                password: password
            )
            isResolving = false
            connectedAddress = config.baseURL
            connectedUsername = username
            isAuthenticated = true
        } catch {
            isResolving = false
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func attemptAutoLogin() async {
        isLoading = true
        do {
            let success = try await authService.tryAutoLogin()
            if success {
                if let creds = try await KeychainService.shared.loadCredentials() {
                    connectedAddress = creds.config.baseURL
                    connectedUsername = creds.username
                }
                isAuthenticated = true
            }
        } catch {
            // Auto-login failed silently — user sees login screen
        }
        isLoading = false
    }

    func logout() async {
        do {
            try await authService.logout()
        } catch {
            // Best-effort logout
        }
        isAuthenticated = false
        password = ""
    }

    // MARK: - Network Scanning

    func scanNetwork() async {
        isScanning = true
        discoveredDevices = []
        let devices = await networkScanner.scan()
        discoveredDevices = devices.filter { $0.type == .synology }
        isScanning = false
        if !discoveredDevices.isEmpty {
            showDevicePicker = true
        }
    }

    func selectDevice(_ device: DiscoveredDevice) {
        connectionMode = .address
        address = device.address
        port = String(device.port)
        useHTTPS = device.port == 5001
        showDevicePicker = false
    }
}
