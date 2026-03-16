import SwiftUI
import Observation

@Observable
@MainActor
final class PlexViewModel {
    // MARK: - Configuration State
    var isConfigured = false
    var serverAddress: String = ""
    var port: String = "32400"
    var token: String = ""
    var useHTTPS: Bool = false

    // MARK: - Settings UI State
    var isTestingConnection = false
    var connectionTestResult: String?
    var isSaving = false
    var settingsError: String?

    // MARK: - Plex Sign-In State
    var isSigningIn = false
    var signInError: String?

    // MARK: - Media Status Cache
    var mediaStatusCache: [String: PlexMediaStatus] = [:]

    // MARK: - Client Playback State
    var availableClients: [PlexResource] = []
    var isLoadingClients = false
    var showClientPicker = false
    var pendingPlaybackItem: (mediaKey: String, taskTitle: String)?
    var playbackError: String?

    // MARK: - Scan State
    var scanningTaskIDs: Set<String> = []

    /// Persisted cache: task ID -> PlexFoundInfo (for tasks confirmed in Plex)
    private var persistedCache: [String: PlexFoundInfo] = [:]
    private static let cacheKey = "plexMediaCache"

    /// Track which task IDs we've already attempted to check this session
    private var checkedTaskIDs: Set<String> = []

    private let plexService: PlexService

    init(plexService: PlexService) {
        self.plexService = plexService
        loadPersistedCache()
    }

    // MARK: - Persistence

    private func loadPersistedCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let decoded = try? JSONDecoder().decode([String: PlexFoundInfo].self, from: data) else {
            return
        }
        persistedCache = decoded
        // Restore found statuses into the live cache
        for (taskID, info) in persistedCache {
            mediaStatusCache[taskID] = .found(info.mediaKey, sectionKey: info.sectionKey)
        }
    }

    private func savePersistedCache() {
        if let data = try? JSONEncoder().encode(persistedCache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func persistFound(taskID: String, mediaKey: String, sectionKey: String) {
        persistedCache[taskID] = PlexFoundInfo(mediaKey: mediaKey, sectionKey: sectionKey)
        savePersistedCache()
    }

    private func removePersistedStatus(taskID: String) {
        persistedCache.removeValue(forKey: taskID)
        savePersistedCache()
    }

    // MARK: - Load Saved Config

    func loadConfig() async {
        let loaded = await plexService.loadSavedConfig()
        if loaded, let config = await plexService.getConfig() {
            serverAddress = config.serverAddress
            port = String(config.port)
            token = config.token
            useHTTPS = config.useHTTPS
            isConfigured = true
        }
    }

    /// Pre-fill server address from NAS address if not already configured
    func prefillAddress(_ address: String) {
        if !isConfigured && serverAddress.isEmpty {
            // Extract just the host (strip port if present)
            let host = address.components(separatedBy: ":").first ?? address
            serverAddress = host
        }
    }

    // MARK: - Save Config

    func saveConfig() async {
        isSaving = true
        settingsError = nil
        let config = PlexConfig(
            serverAddress: serverAddress,
            port: Int(port) ?? 32400,
            token: token,
            useHTTPS: useHTTPS
        )
        do {
            try await plexService.saveConfig(config)
            isConfigured = true
        } catch {
            settingsError = error.localizedDescription
        }
        isSaving = false
    }

    func disconnectPlex() async {
        try? await plexService.clearConfig()
        isConfigured = false
        token = ""
        mediaStatusCache.removeAll()
    }

    // MARK: - Plex Sign-In (PIN Auth)

    func signInWithPlex() async {
        isSigningIn = true
        signInError = nil
        do {
            // 1. Request a PIN
            let pin = try await plexService.requestPIN()
            print("[PlexVM] Got PIN: id=\(pin.id), code=\(pin.code)")

            // 2. Open Safari for user to authorize
            let url = await plexService.authURL(code: pin.code)
            await UIApplication.shared.open(url)

            // 3. Poll for token (up to 2 minutes)
            var authToken: String?
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(2))
                authToken = try await plexService.checkPIN(id: pin.id)
                if authToken != nil { break }
            }

            if let authToken {
                token = authToken
                print("[PlexVM] Got Plex auth token")

                // Auto-save if server address is already set
                if !serverAddress.isEmpty {
                    await saveConfig()
                }
            } else {
                signInError = "Sign-in timed out. Please try again."
            }
        } catch {
            signInError = error.localizedDescription
        }
        isSigningIn = false
    }

    // MARK: - Test Connection

    func testConnection() async {
        isTestingConnection = true
        connectionTestResult = nil
        let config = PlexConfig(
            serverAddress: serverAddress,
            port: Int(port) ?? 32400,
            token: token,
            useHTTPS: useHTTPS
        )
        await plexService.configure(config)
        do {
            let count = try await plexService.testConnection()
            connectionTestResult = "Connected! Found \(count) library section(s)."
        } catch {
            connectionTestResult = "Failed: \(error.localizedDescription)"
        }
        isTestingConnection = false
    }

    // MARK: - Check if Media is in Plex

    func checkPlexStatus(for task: DownloadTask) async {
        guard isConfigured else { return }
        // Only show "checking" if we don't already have a meaningful status
        switch mediaStatusCache[task.id] {
        case nil, .unknown:
            mediaStatusCache[task.id] = .checking
        default:
            break
        }
        do {
            if let result = try await plexService.findMedia(title: task.title, destination: task.destination) {
                mediaStatusCache[task.id] = .found(result.item.key, sectionKey: result.sectionKey)
                persistFound(taskID: task.id, mediaKey: result.item.key, sectionKey: result.sectionKey)
            } else {
                mediaStatusCache[task.id] = .notFound
            }
        } catch {
            print("[PlexVM] checkPlexStatus error for '\(task.title)': \(error.localizedDescription)")
            mediaStatusCache[task.id] = .error(error.localizedDescription)
        }
        checkedTaskIDs.insert(task.id)
    }

    func plexStatus(for taskID: String) -> PlexMediaStatus {
        mediaStatusCache[taskID] ?? .unknown
    }

    /// Returns true if this task is confirmed found in Plex
    func isFoundInPlex(_ taskID: String) -> Bool {
        if case .found = mediaStatusCache[taskID] {
            return true
        }
        return false
    }

    // MARK: - Background Auto-Check

    /// Auto-check all completed tasks that haven't been checked yet
    /// Includes finished, seeding, and paused tasks (paused torrents may have fully downloaded)
    func autoCheckTasks(_ tasks: [DownloadTask]) async {
        guard isConfigured else { return }

        let eligibleTasks = tasks.filter { task in
            (task.status == .finished || task.status == .seeding || task.status == .paused)
            && !checkedTaskIDs.contains(task.id)
            && mediaStatusCache[task.id] == nil
        }

        for task in eligibleTasks {
            await checkPlexStatus(for: task)
        }
    }

    // MARK: - Trigger Plex Scan

    func triggerScan(for task: DownloadTask) async {
        scanningTaskIDs.insert(task.id)
        mediaStatusCache[task.id] = .scanning

        do {
            let nasPath = resolveNASPath(for: task)
            print("[PlexVM] Triggering scan with NAS path: '\(nasPath)'")

            // Check if the download destination is inside any Plex library folder
            let libraryPaths = try await plexService.getVideoLibraryPaths()
            let isInsideLibrary = libraryPaths.contains { nasPath.hasPrefix($0) }

            if !isInsideLibrary {
                let destination = task.destination ?? "unknown"
                let libraryNames = libraryPaths.map { $0.replacingOccurrences(of: "/volume1/", with: "") }
                print("[PlexVM] Download destination '/volume1/\(destination)' is NOT inside any Plex library folder: \(libraryPaths)")
                mediaStatusCache[task.id] = .outsideLibrary(
                    destination: destination,
                    libraries: libraryNames
                )
                scanningTaskIDs.remove(task.id)
                return
            }

            // Destination is inside a library — trigger scan
            if let section = try await plexService.findSectionForPath(nasPath) {
                print("[PlexVM] Matched section '\(section.title)' (key: \(section.key)) for path")
                try await plexService.triggerScan(sectionKey: section.key, path: nasPath)
            } else {
                print("[PlexVM] No exact section match, scanning all video sections")
                try await plexService.triggerScanAllVideoSections()
            }

            // Wait and re-check multiple times (Plex indexing can take a while)
            for attempt in 1...3 {
                let delay = attempt == 1 ? 5 : 10
                print("[PlexVM] Waiting \(delay)s before re-check (attempt \(attempt)/3)")
                try? await Task.sleep(for: .seconds(delay))
                await checkPlexStatus(for: task)
                if case .found = mediaStatusCache[task.id] {
                    print("[PlexVM] Found in Plex after attempt \(attempt)")
                    break
                }
            }
        } catch {
            print("[PlexVM] Scan error: \(error.localizedDescription)")
            mediaStatusCache[task.id] = .error(error.localizedDescription)
        }
        scanningTaskIDs.remove(task.id)
    }

    // MARK: - Play on Client

    func initiatePlayback(for task: DownloadTask) async {
        guard case .found(_, _) = mediaStatusCache[task.id] else { return }

        // Re-verify the media still exists in Plex before playing
        do {
            if let result = try await plexService.findMedia(title: task.title, destination: task.destination) {
                // Update the cached key in case it changed
                mediaStatusCache[task.id] = .found(result.item.key, sectionKey: result.sectionKey)
                persistFound(taskID: task.id, mediaKey: result.item.key, sectionKey: result.sectionKey)
            } else {
                // Media no longer in Plex — remove the found status
                mediaStatusCache[task.id] = .notFound
                removePersistedStatus(taskID: task.id)
                playbackError = "Media is no longer available in Plex. It may have been moved or removed."
                return
            }
        } catch {
            // If verification fails, proceed with cached key
            print("[PlexVM] Verification failed, using cached key: \(error.localizedDescription)")
        }

        // Get the (possibly updated) key
        guard case .found(let currentKey, _) = mediaStatusCache[task.id] else { return }

        isLoadingClients = true
        playbackError = nil
        do {
            let clients = try await plexService.getClients()
            availableClients = clients

            if clients.isEmpty {
                playbackError = "No Plex clients found. Make sure your Apple TV or other Plex client is running."
            } else if clients.count == 1 {
                await playOnClient(clients[0], mediaKey: currentKey)
            } else {
                pendingPlaybackItem = (mediaKey: currentKey, taskTitle: task.title)
                showClientPicker = true
            }
        } catch {
            playbackError = error.localizedDescription
        }
        isLoadingClients = false
    }

    func playOnClient(_ client: PlexResource, mediaKey: String) async {
        do {
            try await plexService.playOnClient(client: client, mediaKey: mediaKey)
        } catch {
            playbackError = error.localizedDescription
        }
    }

    // MARK: - Network Scanning

    var isScanningNetwork = false
    var discoveredPlexServers: [DiscoveredDevice] = []
    var showPlexDevicePicker = false

    private let networkScanner = NetworkScannerService()

    func scanForPlexServers() async {
        isScanningNetwork = true
        discoveredPlexServers = []
        let devices = await networkScanner.scan()
        discoveredPlexServers = devices.filter { $0.type == .plex }
        isScanningNetwork = false
        if !discoveredPlexServers.isEmpty {
            showPlexDevicePicker = true
        }
    }

    func selectPlexServer(_ device: DiscoveredDevice) {
        serverAddress = device.address
        port = String(device.port)
        showPlexDevicePicker = false
    }

    // MARK: - Helpers

    private func resolveNASPath(for task: DownloadTask) -> String {
        guard let destination = task.destination else {
            print("[PlexVM] No destination for task '\(task.title)', using empty path")
            return ""
        }
        let cleaned = destination.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = "/volume1/\(cleaned)/\(task.title)"
        print("[PlexVM] resolveNASPath: destination='\(destination)' -> '\(path)'")
        return path
    }
}
