import Foundation

actor PlexService {
    private var config: PlexConfig?
    private let session: URLSession
    private let keychain: KeychainService
    private var cachedSections: [PlexLibrarySection]?

    init(keychain: KeychainService = .shared) {
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = 10
        urlConfig.timeoutIntervalForResource = 20
        self.session = URLSession(
            configuration: urlConfig,
            delegate: InsecureCertDelegate(),
            delegateQueue: nil
        )
        self.keychain = keychain
    }

    // MARK: - Configuration

    var isConfigured: Bool { config != nil }

    func configure(_ config: PlexConfig) {
        self.config = config
        self.cachedSections = nil
    }

    func getConfig() -> PlexConfig? { config }

    func loadSavedConfig() async -> Bool {
        do {
            guard let data = try await keychain.load(key: "plex_config") else { return false }
            let saved = try JSONDecoder().decode(PlexConfig.self, from: data)
            self.config = saved
            return true
        } catch {
            return false
        }
    }

    func saveConfig(_ config: PlexConfig) async throws {
        let data = try JSONEncoder().encode(config)
        try await keychain.save(key: "plex_config", data: data)
        self.config = config
        self.cachedSections = nil
    }

    func clearConfig() async throws {
        try await keychain.delete(key: "plex_config")
        self.config = nil
        self.cachedSections = nil
    }

    // MARK: - Plex PIN Authentication

    private static let plexClientID = "TorrentStation-iOS"

    /// Request a new PIN from plex.tv. Returns (pin ID, pin code).
    func requestPIN() async throws -> (id: Int, code: String) {
        var components = URLComponents(string: "https://plex.tv/api/v2/pins")!
        components.queryItems = [
            URLQueryItem(name: "strong", value: "true"),
            URLQueryItem(name: "X-Plex-Product", value: "TorrentStation"),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: Self.plexClientID),
        ]

        guard let url = components.url else { throw PlexError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw PlexError.httpError(statusCode: http.statusCode)
        }

        struct PINResponse: Decodable {
            let id: Int
            let code: String
        }

        let pin = try JSONDecoder().decode(PINResponse.self, from: data)
        return (pin.id, pin.code)
    }

    /// Build the URL the user should open in Safari to authorize the PIN
    func authURL(code: String) -> URL {
        var components = URLComponents(string: "https://app.plex.tv/auth")!
        components.fragment = "?clientID=\(Self.plexClientID)&code=\(code)&context%5Bdevice%5D%5Bproduct%5D=TorrentStation"
        return components.url!
    }

    /// Poll the PIN to check if the user has authorized. Returns the auth token or nil.
    func checkPIN(id: Int) async throws -> String? {
        var components = URLComponents(string: "https://plex.tv/api/v2/pins/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "X-Plex-Client-Identifier", value: Self.plexClientID),
        ]

        guard let url = components.url else { throw PlexError.invalidURL }

        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw PlexError.httpError(statusCode: http.statusCode)
        }

        struct PINCheckResponse: Decodable {
            let authToken: String?
        }

        let result = try JSONDecoder().decode(PINCheckResponse.self, from: data)
        return result.authToken
    }

    // MARK: - HTTP Helpers

    private func plexRequest<T: Decodable>(path: String, queryParams: [String: String] = [:]) async throws -> T {
        guard let config else { throw PlexError.notConfigured }

        var components = URLComponents(string: "\(config.baseURL)\(path)")
        var queryItems = [URLQueryItem(name: "X-Plex-Token", value: config.token)]
        for (key, value) in queryParams {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else { throw PlexError.invalidURL }

        print("[PlexService] Request: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                print("[PlexService] Response status: \(http.statusCode)")
                if !(200...299).contains(http.statusCode) {
                    let preview = String(data: data, encoding: .utf8)?.prefix(300) ?? "non-utf8"
                    print("[PlexService] Error body: \(preview)")
                    throw PlexError.httpError(statusCode: http.statusCode)
                }
            }
            let preview = String(data: data, encoding: .utf8)?.prefix(500) ?? "non-utf8"
            print("[PlexService] Response body preview: \(preview)")
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as PlexError {
            throw error
        } catch let error as DecodingError {
            print("[PlexService] Decode error: \(error)")
            throw PlexError.decodingError(error)
        } catch {
            print("[PlexService] Connection error: \(error)")
            throw PlexError.connectionFailed(error)
        }
    }

    private func plexCommand(path: String, queryParams: [String: String] = [:]) async throws {
        guard let config else { throw PlexError.notConfigured }

        var components = URLComponents(string: "\(config.baseURL)\(path)")
        var queryItems = [URLQueryItem(name: "X-Plex-Token", value: config.token)]
        for (key, value) in queryParams {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else { throw PlexError.invalidURL }

        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw PlexError.httpError(statusCode: http.statusCode)
        }
    }

    // MARK: - Library Sections

    func getLibrarySections(forceRefresh: Bool = false) async throws -> [PlexLibrarySection] {
        if !forceRefresh, let cached = cachedSections { return cached }
        let container: PlexMediaContainer<PlexSectionsResponse> = try await plexRequest(path: "/library/sections")
        let sections = container.MediaContainer.Directory ?? []
        self.cachedSections = sections
        return sections
    }

    // MARK: - Search for Media

    func findMedia(title: String, destination: String? = nil) async throws -> (item: PlexMediaItem, sectionKey: String)? {
        let sections = try await getLibrarySections()
        let videoSections = sections.filter { $0.type == "movie" || $0.type == "show" }
        let cleanTitle = cleanTorrentTitle(title)
        print("[PlexService] Searching for: '\(cleanTitle)' (original: '\(title)')")

        // Strategy 1: Search by title (cleaned)
        for section in videoSections {
            if let result = try await searchSection(section.key, title: cleanTitle) {
                return result
            }
        }

        // Strategy 2: Strip year/brackets and retry
        let simplerTitle = stripYearAndBrackets(cleanTitle)
        if simplerTitle != cleanTitle {
            print("[PlexService] Retrying with simpler title: '\(simplerTitle)'")
            for section in videoSections {
                if let result = try await searchSection(section.key, title: simplerTitle) {
                    return result
                }
            }
        }

        // Strategy 3: Scan all items in video sections and match by file path
        // The torrent title often appears in the file path on disk
        print("[PlexService] Title search failed, trying file path matching for '\(title)'")
        for section in videoSections {
            if let result = try await searchSectionByFilePath(section.key, torrentTitle: title) {
                return result
            }
        }

        return nil
    }

    private func searchSection(_ sectionKey: String, title: String) async throws -> (item: PlexMediaItem, sectionKey: String)? {
        let container: PlexMediaContainer<PlexSearchResponse> = try await plexRequest(
            path: "/library/sections/\(sectionKey)/all",
            queryParams: ["title": title, "includeMedia": "1"]
        )
        if let items = container.MediaContainer.Metadata {
            print("[PlexService] Section \(sectionKey): found \(items.count) result(s) for '\(title)'")
            for item in items {
                print("[PlexService]   - '\(item.title)' files: \(item.filePaths)")
            }
            if let first = items.first {
                return (first, sectionKey)
            }
        }
        return nil
    }

    /// Search a section by matching the torrent title against file paths in Plex
    private func searchSectionByFilePath(_ sectionKey: String, torrentTitle: String) async throws -> (item: PlexMediaItem, sectionKey: String)? {
        // Get all items in the section with file info
        let container: PlexMediaContainer<PlexSearchResponse> = try await plexRequest(
            path: "/library/sections/\(sectionKey)/all",
            queryParams: ["includeMedia": "1"]
        )
        guard let items = container.MediaContainer.Metadata else { return nil }

        let titleLower = torrentTitle.lowercased()
        for item in items {
            for filePath in item.filePaths {
                if filePath.lowercased().contains(titleLower) {
                    print("[PlexService] File path match: '\(item.title)' at '\(filePath)'")
                    return (item, sectionKey)
                }
            }
        }
        return nil
    }

    func findSectionForPath(_ path: String) async throws -> PlexLibrarySection? {
        let sections = try await getLibrarySections()
        print("[PlexService] findSectionForPath: looking for '\(path)'")
        for section in sections {
            guard let locations = section.locations else { continue }
            for location in locations {
                print("[PlexService]   Section '\(section.title)' location: '\(location.path)'")
                if path.hasPrefix(location.path) {
                    return section
                }
            }
        }
        print("[PlexService] No section matched the path")
        return nil
    }

    /// Returns all unique library location paths for video sections
    func getVideoLibraryPaths() async throws -> [String] {
        let sections = try await getLibrarySections()
        let videoSections = sections.filter { $0.type == "movie" || $0.type == "show" }
        return videoSections.compactMap { $0.locations }.flatMap { $0 }.map(\.path)
    }

    // MARK: - Trigger Library Scan

    func triggerScan(sectionKey: String, path: String? = nil) async throws {
        var params: [String: String] = [:]
        if let path { params["path"] = path }
        try await plexCommand(path: "/library/sections/\(sectionKey)/refresh", queryParams: params)
    }

    func triggerScanAllVideoSections(path: String? = nil) async throws {
        let sections = try await getLibrarySections()
        for section in sections where section.type == "movie" || section.type == "show" {
            try await triggerScan(sectionKey: section.key, path: path)
        }
    }

    // MARK: - Clients

    func getClients() async throws -> [PlexResource] {
        guard let config else { throw PlexError.notConfigured }

        // Query plex.tv cloud API for all devices linked to this account
        var components = URLComponents(string: "https://plex.tv/api/v2/resources")!
        components.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
        ]

        guard let url = components.url else { throw PlexError.invalidURL }

        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue(config.token, forHTTPHeaderField: "X-Plex-Token")
        request.addValue("TorrentStation", forHTTPHeaderField: "X-Plex-Client-Identifier")

        print("[PlexService] Fetching resources from plex.tv")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                print("[PlexService] plex.tv resources status: \(http.statusCode)")
                if !(200...299).contains(http.statusCode) {
                    throw PlexError.httpError(statusCode: http.statusCode)
                }
            }
            let resources = try JSONDecoder().decode([PlexResource].self, from: data)
            let players = resources.filter { $0.canPlayback }
            print("[PlexService] Found \(players.count) player(s): \(players.map { $0.displayName })")
            return players
        } catch let error as PlexError {
            throw error
        } catch let error as DecodingError {
            print("[PlexService] Resources decode error: \(error)")
            throw PlexError.decodingError(error)
        } catch {
            print("[PlexService] Resources connection error: \(error)")
            throw PlexError.connectionFailed(error)
        }
    }

    // MARK: - Server Identity

    /// Fetch the server's machineIdentifier from plex.tv resources
    private func getServerMachineIdentifier() async throws -> String {
        guard let config else { throw PlexError.notConfigured }

        var components = URLComponents(string: "https://plex.tv/api/v2/resources")!
        components.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
        ]

        guard let url = components.url else { throw PlexError.invalidURL }

        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue(config.token, forHTTPHeaderField: "X-Plex-Token")
        request.addValue("TorrentStation", forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw PlexError.httpError(statusCode: http.statusCode)
        }

        let resources = try JSONDecoder().decode([PlexResource].self, from: data)

        // Find the server resource — match by address or just find the first "server" provider
        // Try matching the configured server address against resource connections first
        let configHost = config.serverAddress.lowercased()
        for resource in resources where resource.provides?.contains("server") == true {
            if let connections = resource.connections {
                for conn in connections {
                    if conn.uri.lowercased().contains(configHost) {
                        print("[PlexService] Matched server: '\(resource.name)' (id: \(resource.clientIdentifier))")
                        return resource.clientIdentifier
                    }
                }
            }
        }

        // Fallback: return the first server resource
        if let server = resources.first(where: { $0.provides?.contains("server") == true }) {
            print("[PlexService] Using first server resource: '\(server.name)' (id: \(server.clientIdentifier))")
            return server.clientIdentifier
        }

        throw PlexError.playbackFailed("Could not find Plex server machineIdentifier")
    }

    // MARK: - Remote Playback

    func playOnClient(client: PlexResource, mediaKey: String) async throws {
        guard let config else { throw PlexError.notConfigured }

        // Get the server's machineIdentifier (not the client's)
        let serverMachineId = try await getServerMachineIdentifier()
        print("[PlexService] Server machineIdentifier: \(serverMachineId)")
        print("[PlexService] Client identifier: \(client.clientIdentifier)")

        // Find a connection URI for the client (prefer local)
        guard let connection = client.connections?.first(where: { $0.local == true }) ?? client.connections?.first else {
            throw PlexError.playbackFailed("No connection available for \(client.name)")
        }

        let playbackURL = "\(connection.uri)/player/playback/playMedia"
        guard var components = URLComponents(string: playbackURL) else { throw PlexError.invalidURL }

        components.queryItems = [
            URLQueryItem(name: "key", value: mediaKey),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "machineIdentifier", value: serverMachineId),
            URLQueryItem(name: "address", value: config.serverAddress),
            URLQueryItem(name: "port", value: String(config.port)),
            URLQueryItem(name: "protocol", value: config.useHTTPS ? "https" : "http"),
            URLQueryItem(name: "commandID", value: "1"),
            URLQueryItem(name: "type", value: "video"),
        ]

        guard let url = components.url else { throw PlexError.invalidURL }

        print("[PlexService] Sending playback command to: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        // X-Plex-Target-Client-Identifier tells the server which client should play
        request.addValue(client.clientIdentifier, forHTTPHeaderField: "X-Plex-Target-Client-Identifier")
        request.addValue("TorrentStation", forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue("TorrentStation", forHTTPHeaderField: "X-Plex-Device-Name")
        request.addValue(config.token, forHTTPHeaderField: "X-Plex-Token")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                print("[PlexService] Playback response status: \(http.statusCode)")
                if !(200...299).contains(http.statusCode) {
                    let body = String(data: data, encoding: .utf8)?.prefix(500) ?? "no body"
                    print("[PlexService] Playback error body: \(body)")
                    throw PlexError.playbackFailed("Client returned HTTP \(http.statusCode)")
                }
            }
        } catch let error as PlexError {
            throw error
        } catch {
            print("[PlexService] Playback connection error: \(error)")
            throw PlexError.playbackFailed("Connection to client failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Title Cleaning

    private func cleanTorrentTitle(_ title: String) -> String {
        var cleaned = title
        // Remove file extension if present
        let ext = (cleaned as NSString).pathExtension.lowercased()
        if MediaHelper.mediaExtensions.contains(ext) {
            cleaned = (cleaned as NSString).deletingPathExtension
        }
        // Replace dots/underscores with spaces
        cleaned = cleaned.replacingOccurrences(of: ".", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")

        // Remove content in square brackets like [TGx], [1080p], [WEBRip]
        cleaned = cleaned.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)

        // Truncate at known quality/codec markers
        let markers = ["1080p", "720p", "2160p", "4K", "x264", "x265", "HEVC",
                        "WEB-DL", "WEB DL", "WEBRip", "BluRay", "BDRip", "HDRip",
                        "DVDRip", "REMUX", "AAC", "DTS", "FLAC", "S0", "S1", "S2"]
        for marker in markers {
            if let range = cleaned.range(of: marker, options: .caseInsensitive) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }
        // Collapse multiple spaces
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Further simplify title by removing year in parentheses and any remaining brackets
    private func stripYearAndBrackets(_ title: String) -> String {
        var result = title
        // Remove (2023), (2024), etc.
        result = result.replacingOccurrences(of: #"\(\d{4}\)"#, with: "", options: .regularExpression)
        // Remove any remaining parenthesized content
        result = result.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        // Collapse spaces
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testConnection() async throws -> Int {
        let sections = try await getLibrarySections(forceRefresh: true)
        return sections.count
    }
}
