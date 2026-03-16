import Foundation

// MARK: - Generic Response Wrapper
// Plex wraps all JSON responses in a "MediaContainer" envelope

nonisolated struct PlexMediaContainer<T: Decodable>: Decodable {
    let MediaContainer: T
}

// MARK: - Library Sections

nonisolated struct PlexSectionsResponse: Decodable {
    let size: Int?
    let Directory: [PlexLibrarySection]?
}

nonisolated struct PlexLibrarySection: Decodable, Identifiable, Sendable {
    let key: String
    let title: String
    let type: String
    let locations: [PlexLocation]?

    enum CodingKeys: String, CodingKey {
        case key, title, type
        case locations = "Location"
    }

    var id: String { key }
}

nonisolated struct PlexLocation: Decodable, Sendable {
    let id: Int
    let path: String
}

// MARK: - Library Search Results

nonisolated struct PlexSearchResponse: Decodable {
    let size: Int?
    let Metadata: [PlexMediaItem]?
}

nonisolated struct PlexMediaItem: Decodable, Identifiable, Sendable {
    let ratingKey: String
    let key: String
    let title: String
    let type: String
    let year: Int?
    let duration: Int?
    let Media: [PlexMedia]?

    var id: String { ratingKey }

    /// All file paths associated with this media item
    var filePaths: [String] {
        Media?.flatMap { $0.Part?.map(\.file) ?? [] } ?? []
    }
}

nonisolated struct PlexMedia: Decodable, Sendable {
    let Part: [PlexMediaPart]?
}

nonisolated struct PlexMediaPart: Decodable, Sendable {
    let file: String
}

// MARK: - Plex Clients (from plex.tv/api/v2/resources)

nonisolated struct PlexResource: Decodable, Identifiable, Sendable {
    let name: String
    let product: String?
    let clientIdentifier: String
    let provides: String?
    let connections: [PlexResourceConnection]?

    var id: String { clientIdentifier }

    var displayName: String {
        if let product {
            return "\(name) (\(product))"
        }
        return name
    }

    var canPlayback: Bool {
        provides?.contains("player") ?? false
    }
}

nonisolated struct PlexResourceConnection: Decodable, Sendable {
    let uri: String
    let local: Bool?
    let connectionProtocol: String?

    enum CodingKeys: String, CodingKey {
        case uri, local
        case connectionProtocol = "protocol"
    }
}

// Legacy /clients response (kept as fallback)
nonisolated struct PlexClientsResponse: Decodable {
    let size: Int?
    let Server: [PlexClient]?
}

nonisolated struct PlexClient: Decodable, Identifiable, Sendable {
    let name: String
    let host: String
    let port: Int?
    let address: String?
    let machineIdentifier: String
    let product: String?
    let protocolCapabilities: String?

    var id: String { machineIdentifier }

    var displayName: String {
        if let product {
            return "\(name) (\(product))"
        }
        return name
    }

    var canPlayback: Bool {
        protocolCapabilities?.contains("playback") ?? false
    }
}

// MARK: - Configuration

nonisolated struct PlexConfig: Codable, Equatable, Sendable {
    var serverAddress: String
    var port: Int
    var token: String
    var useHTTPS: Bool

    var baseURL: String {
        let scheme = useHTTPS ? "https" : "http"
        // Strip any scheme the user may have entered in the address field
        var host = serverAddress
        for prefix in ["https://", "http://", "http//", "https//"] {
            if host.lowercased().hasPrefix(prefix) {
                host = String(host.dropFirst(prefix.count))
            }
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(scheme)://\(host):\(port)"
    }
}

// MARK: - Media Status

enum PlexMediaStatus: Sendable {
    case unknown
    case checking
    case notFound
    case found(String, sectionKey: String) // mediaKey, sectionKey
    case scanning
    case outsideLibrary(destination: String, libraries: [String])
    case error(String)
}

/// Persisted info about a task's Plex match
struct PlexFoundInfo: Codable, Sendable {
    let mediaKey: String
    let sectionKey: String
}

// MARK: - Errors

enum PlexError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpError(statusCode: Int)
    case decodingError(Error)
    case connectionFailed(Error)
    case noLibrarySections
    case mediaNotFound
    case noClientsAvailable
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Plex is not configured. Add your Plex token in Settings."
        case .invalidURL: "Invalid Plex server URL"
        case .httpError(let code): "Plex HTTP error \(code)"
        case .decodingError(let err): "Failed to decode Plex response: \(err.localizedDescription)"
        case .connectionFailed(let err): "Cannot connect to Plex: \(err.localizedDescription)"
        case .noLibrarySections: "No Plex library sections found"
        case .mediaNotFound: "Media not found in Plex library"
        case .noClientsAvailable: "No Plex clients available for playback"
        case .playbackFailed(let msg): "Playback failed: \(msg)"
        }
    }
}
