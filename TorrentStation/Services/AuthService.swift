import Foundation

actor AuthService {
    private let client: SynologyClient
    private let keychain: KeychainService
    private let quickConnectService = QuickConnectService()

    init(client: SynologyClient, keychain: KeychainService = .shared) {
        self.client = client
        self.keychain = keychain
    }

    func login(config: ConnectionConfig, username: String, password: String) async throws -> String {
        await client.configure(config: config)
        try await client.discoverAPIs()

        let response: SynologyResponse<AuthResponse> = try await client.apiRequest(
            api: "SYNO.API.Auth",
            method: "login",
            version: 6,
            extraParams: [
                "account": username,
                "passwd": password,
                "session": "DownloadStation",
                "format": "sid"
            ]
        )

        guard let sid = response.data?.sid else {
            throw SynologyAPIError.notAuthenticated
        }

        await client.setSid(sid)

        // Also login with FileStation session for media streaming
        await loginFileStation(username: username, password: password)

        let creds = StoredCredentials(config: config, username: username, password: password)
        try await keychain.saveCredentials(creds)

        return sid
    }

    /// Login via QuickConnect ID — resolves the ID first, then delegates to normal login.
    func loginWithQuickConnect(
        quickConnectID: String,
        username: String,
        password: String
    ) async throws -> (String, ConnectionConfig) {
        let resolved = try await quickConnectService.resolve(quickConnectID: quickConnectID)
        var config = resolved
        config.quickConnectID = quickConnectID
        let sid = try await login(config: config, username: username, password: password)
        return (sid, config)
    }

    /// Login to FileStation session (best-effort, non-throwing)
    private func loginFileStation(username: String, password: String) async {
        do {
            let response: SynologyResponse<AuthResponse> = try await client.apiRequest(
                api: "SYNO.API.Auth",
                method: "login",
                version: 6,
                extraParams: [
                    "account": username,
                    "passwd": password,
                    "session": "FileStation",
                    "format": "sid"
                ]
            )
            if let fsSid = response.data?.sid {
                await client.setFileStationSid(fsSid)
            }
        } catch {
            // FileStation login failed — streaming may not work, but don't block the main login
            print("[AuthService] FileStation session login failed: \(error)")
        }
    }

    func logout() async throws {
        // Logout FileStation session if present
        if await client.getFileStationSid() != nil {
            let _: SynologyResponse<EmptyResponse>? = try? await client.apiRequest(
                api: "SYNO.API.Auth",
                method: "logout",
                version: 1,
                extraParams: ["session": "FileStation"],
                useFileStationSession: true
            )
            await client.setFileStationSid(nil)
        }

        let _: SynologyResponse<EmptyResponse> = try await client.apiRequest(
            api: "SYNO.API.Auth",
            method: "logout",
            version: 1,
            extraParams: ["session": "DownloadStation"]
        )
        await client.setSid(nil)
        try await keychain.deleteCredentials()
    }

    func tryAutoLogin() async throws -> Bool {
        guard let creds = try await keychain.loadCredentials() else {
            return false
        }

        // If this was a QuickConnect connection, re-resolve in case IP changed
        if creds.config.isQuickConnect, let qcID = creds.config.quickConnectID {
            do {
                _ = try await loginWithQuickConnect(
                    quickConnectID: qcID,
                    username: creds.username,
                    password: creds.password
                )
                return true
            } catch {
                // If re-resolution fails, try the last known address as fallback
                print("[Auth] QuickConnect re-resolve failed, trying cached address: \(error)")
            }
        }

        _ = try await login(
            config: creds.config,
            username: creds.username,
            password: creds.password
        )
        return true
    }
}
