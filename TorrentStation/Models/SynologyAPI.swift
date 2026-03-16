import Foundation

// MARK: - Generic API Response

nonisolated struct SynologyResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: SynologyError?
}

nonisolated struct SynologyError: Decodable {
    let code: Int
}

nonisolated struct EmptyResponse: Decodable {}

// MARK: - API Info Discovery

nonisolated struct APIInfo: Decodable {
    let path: String
    let minVersion: Int
    let maxVersion: Int
}

// MARK: - Auth

nonisolated struct AuthResponse: Decodable {
    let sid: String
}

// MARK: - Task List

nonisolated struct TaskListData: Decodable {
    let total: Int
    let offset: Int
    let tasks: [RawTask]
}

nonisolated struct RawTask: Decodable, Identifiable {
    let id: String
    let title: String
    let status: String
    let size: Int64
    let type: String?
    let additional: RawTaskAdditional?
}

nonisolated struct RawTaskAdditional: Decodable {
    let transfer: RawTaskTransfer?
    let detail: RawTaskDetail?
}

nonisolated struct RawTaskTransfer: Decodable {
    let size_downloaded: Int64
    let size_uploaded: Int64
    let speed_download: Int64
    let speed_upload: Int64
}

nonisolated struct RawTaskDetail: Decodable {
    let destination: String?
    let create_time: Int64?
    let uri: String?
}

// MARK: - Statistics

nonisolated struct StatisticData: Decodable {
    let speed_download: Int64
    let speed_upload: Int64
}

// MARK: - Domain Model

nonisolated enum TaskStatus: String, CaseIterable, Sendable {
    case downloading, paused, finished, seeding, waiting, error
    case hashChecking = "hash_checking"
    case fileHostingWaiting = "filehosting_waiting"
    case extracting, unknown

    init(rawValue: String) {
        switch rawValue {
        case "downloading": self = .downloading
        case "paused": self = .paused
        case "finished": self = .finished
        case "seeding": self = .seeding
        case "waiting": self = .waiting
        case "error": self = .error
        case "hash_checking": self = .hashChecking
        case "filehosting_waiting": self = .fileHostingWaiting
        case "extracting": self = .extracting
        default: self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .downloading: "Downloading"
        case .paused: "Paused"
        case .finished: "Completed"
        case .seeding: "Seeding"
        case .waiting: "Waiting"
        case .error: "Error"
        case .hashChecking: "Checking"
        case .fileHostingWaiting: "Waiting"
        case .extracting: "Extracting"
        case .unknown: "Unknown"
        }
    }
}

nonisolated struct DownloadTask: Identifiable, Sendable {
    let id: String
    let title: String
    let status: TaskStatus
    let totalSize: Int64
    let downloadedSize: Int64
    let uploadedSize: Int64
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let progress: Double
    let destination: String?
    let createTime: Date?
    let uri: String?

    /// Whether this task likely contains media based on its title
    var isLikelyMedia: Bool {
        let ext = (title as NSString).pathExtension.lowercased()
        if MediaHelper.mediaExtensions.contains(ext) { return true }
        // Many torrent titles don't have extensions — check for common media keywords
        let lower = title.lowercased()
        return lower.contains("1080p") || lower.contains("720p") || lower.contains("2160p")
            || lower.contains("4k") || lower.contains("x264") || lower.contains("x265")
            || lower.contains("hevc") || lower.contains("web-dl") || lower.contains("bluray")
            || lower.contains("bdrip") || lower.contains("webrip")
    }

    /// Whether streaming is possible (finished or seeding with known destination)
    var canStream: Bool {
        (status == .finished || status == .seeding) && destination != nil && isLikelyMedia
    }

    init(from raw: RawTask) {
        self.id = raw.id
        self.title = raw.title
        self.status = TaskStatus(rawValue: raw.status)
        self.totalSize = raw.size
        self.downloadedSize = raw.additional?.transfer?.size_downloaded ?? 0
        self.uploadedSize = raw.additional?.transfer?.size_uploaded ?? 0
        self.downloadSpeed = raw.additional?.transfer?.speed_download ?? 0
        self.uploadSpeed = raw.additional?.transfer?.speed_upload ?? 0
        self.destination = raw.additional?.detail?.destination
        self.uri = raw.additional?.detail?.uri
        if let ts = raw.additional?.detail?.create_time, ts > 0 {
            self.createTime = Date(timeIntervalSince1970: TimeInterval(ts))
        } else {
            self.createTime = nil
        }
        if raw.size > 0 {
            self.progress = Double(self.downloadedSize) / Double(raw.size)
        } else {
            self.progress = 0.0
        }
    }
}

// MARK: - Media Helpers

nonisolated enum MediaHelper {
    static let mediaExtensions: Set<String> = [
        "mp4", "mkv", "avi", "mov", "wmv", "flv", "m4v", "webm",
        "mpg", "mpeg", "ts", "vob", "3gp",
        "mp3", "flac", "aac", "ogg", "wav", "wma", "m4a"
    ]

    static let videoExtensions: Set<String> = [
        "mp4", "mkv", "avi", "mov", "wmv", "flv", "m4v", "webm",
        "mpg", "mpeg", "ts", "vob", "3gp"
    ]

    static func isMediaFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return mediaExtensions.contains(ext)
    }

    static func isVideoFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }
}

// MARK: - FileStation Models

nonisolated struct FileListData: Decodable {
    let total: Int
    let offset: Int
    let files: [FileItem]
}

nonisolated struct FileItem: Decodable, Identifiable, Sendable {
    let path: String
    let name: String
    let isdir: Bool
    let additional: FileItemAdditional?

    var id: String { path }

    var isMedia: Bool { MediaHelper.isMediaFile(name) }
    var isVideo: Bool { MediaHelper.isVideoFile(name) }
}

/// FileStation returns `additional.size` in different formats depending on DSM version:
///   - As a plain number: `"size": 11119922991`
///   - As an object with total: `"size": {"total": 11119922991}`
///   - As an object with string total: `"size": {"total": "11119922991"}`
nonisolated struct FileItemAdditional: Decodable, Sendable {
    let size: Int64?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let intValue = try? container.decode(Int64.self, forKey: .size) {
            // Plain number: "size": 11119922991
            size = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .size) {
            // Plain string: "size": "11119922991"
            size = Int64(stringValue)
        } else if let obj = try? container.decode(FileItemSizeObject.self, forKey: .size) {
            // Nested object: "size": {"total": ...}
            size = obj.total
        } else {
            size = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case size
    }
}

/// Helper for the nested object format of size
private nonisolated struct FileItemSizeObject: Decodable {
    let total: Int64

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intValue = try? container.decode(Int64.self, forKey: .total) {
            total = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .total) {
            total = Int64(stringValue) ?? 0
        } else {
            total = 0
        }
    }

    private enum CodingKeys: String, CodingKey {
        case total
    }
}

// MARK: - FileStation Shared Folders

nonisolated struct ShareListData: Decodable {
    let total: Int
    let offset: Int
    let shares: [ShareItem]
}

nonisolated struct ShareItem: Decodable, Sendable {
    let path: String
    let name: String
    let isdir: Bool
}

// MARK: - Filter Categories

enum TaskFilter: String, CaseIterable, Identifiable {
    case all, downloading, seeding, paused, completed, error

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "All"
        case .downloading: "Downloading"
        case .seeding: "Seeding"
        case .paused: "Paused"
        case .completed: "Completed"
        case .error: "Error"
        }
    }

    func matches(_ task: DownloadTask) -> Bool {
        switch self {
        case .all: true
        case .downloading:
            ![.seeding, .paused, .finished, .error].contains(task.status)
        case .seeding: task.status == .seeding
        case .paused: task.status == .paused
        case .completed: task.status == .finished
        case .error: task.status == .error
        }
    }
}

// MARK: - Error Types

enum SynologyAPIError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int)
    case apiError(code: Int)
    case decodingError(Error)
    case notAuthenticated
    case connectionFailed(Error)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid server URL"
        case .httpError(let code): "HTTP error \(code)"
        case .apiError(let code): "API error (code \(code)): \(Self.apiErrorMessage(code))"
        case .decodingError(let err): "Failed to decode response: \(err.localizedDescription)"
        case .notAuthenticated: "Not logged in"
        case .connectionFailed(let err): "Connection failed: \(err.localizedDescription)"
        case .timeout: "Request timed out"
        }
    }

    static func apiErrorMessage(_ code: Int) -> String {
        switch code {
        case 101: "Invalid parameter"
        case 102: "API does not exist"
        case 103: "Method does not exist"
        case 104: "Version not supported"
        case 105: "Permission denied"
        case 106: "Session timeout"
        case 107: "Duplicate login"
        case 400: "No such task"
        case 401: "Invalid task"
        case 402: "Invalid task creation URL"
        default: "Unknown error"
        }
    }
}
