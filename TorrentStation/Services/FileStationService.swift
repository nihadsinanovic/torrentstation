import Foundation

actor FileStationService {
    private let client: SynologyClient
    private var hasFileStationSession = false
    private var sharedFolders: [ShareItem]?

    init(client: SynologyClient) {
        self.client = client
    }

    /// Ensures we have a FileStation session — required by Synology API
    private func ensureFileStationSession() async throws {
        if hasFileStationSession { return }

        // Check if we already have a FileStation SID set by AuthService
        if await client.getFileStationSid() != nil {
            hasFileStationSession = true
            return
        }

        // Fallback: try using the DownloadStation SID (works on many DSM versions)
        if await client.getSid() != nil {
            hasFileStationSession = true
        }
    }

    /// Discovers shared folders on the NAS (cached after first call)
    func listSharedFolders() async throws -> [ShareItem] {
        if let cached = sharedFolders { return cached }

        try await ensureFileStationSession()

        let response: SynologyResponse<ShareListData> = try await client.apiRequest(
            api: "SYNO.FileStation.List",
            method: "list_share",
            version: 2,
            useFileStationSession: true
        )
        let shares = response.data?.shares ?? []
        self.sharedFolders = shares
        return shares
    }

    /// Resolves a Download Station destination path to a FileStation path.
    /// Download Station stores destinations like "Videos/Movies" (relative to volume root).
    /// FileStation expects paths like "/video/Movies" where "/video" is a shared folder.
    /// We discover shared folders and find the matching root.
    func resolveDestinationPath(_ destination: String) async -> String {
        var cleanDest = destination
        // Strip "Shared/" prefix if present (DSM UI artifact)
        if cleanDest.hasPrefix("Shared/") {
            cleanDest = String(cleanDest.dropFirst("Shared/".count))
        }
        cleanDest = cleanDest.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Try to match against known shared folders
        if let shares = try? await listSharedFolders() {
            print("[FileStationService] Shared folders: \(shares.map { "\($0.name) -> \($0.path)" })")
            print("[FileStationService] Resolving destination: '\(cleanDest)'")

            let components = cleanDest.split(separator: "/", maxSplits: 1)
            if let firstComponent = components.first {
                let firstDir = String(firstComponent)
                let rest = components.count > 1 ? String(components[1]) : nil

                for share in shares {
                    // Case-insensitive match on name
                    if share.name.caseInsensitiveCompare(firstDir) == .orderedSame {
                        let resolved = rest != nil ? "\(share.path)/\(rest!)" : share.path
                        print("[FileStationService] Matched share '\(share.name)' -> resolved: \(resolved)")
                        return resolved
                    }
                    // Also check if destination starts with the share's actual path name
                    // e.g., share path is "/volume1/video" and dest is "video/Movies"
                    let shareName = (share.path as NSString).lastPathComponent
                    if shareName.caseInsensitiveCompare(firstDir) == .orderedSame {
                        let resolved = rest != nil ? "\(share.path)/\(rest!)" : share.path
                        print("[FileStationService] Matched share path component '\(shareName)' -> resolved: \(resolved)")
                        return resolved
                    }
                }

                print("[FileStationService] No share matched '\(firstDir)'")
            }
        } else {
            print("[FileStationService] Failed to list shared folders")
        }

        // Fallback: just prepend / to the cleaned destination
        return "/\(cleanDest)"
    }

    /// Builds a list of candidate FileStation paths for a destination + subfolder.
    private func candidatePaths(destination: String, subfolder: String) async -> [String] {
        var cleanDest = destination
        if cleanDest.hasPrefix("Shared/") {
            cleanDest = String(cleanDest.dropFirst("Shared/".count))
        }
        cleanDest = cleanDest.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let resolvedDest = await resolveDestinationPath(destination)
        var candidates: [String] = []

        // 1. Resolved path (share-matched)
        let resolved = "\(resolvedDest)/\(subfolder)"
        candidates.append(resolved)

        // 2. If no share matched, try each share as a parent
        //    e.g., destination "Videos/Movies" might live under /Shared/Videos/Movies
        if let shares = try? await listSharedFolders() {
            for share in shares {
                let candidate = "\(share.path)/\(cleanDest)/\(subfolder)"
                if !candidates.contains(candidate) {
                    candidates.append(candidate)
                }
            }
        }

        // 3. Try with /volume1 prefix
        let volumePath = "/volume1/\(cleanDest)/\(subfolder)"
        if !candidates.contains(volumePath) {
            candidates.append(volumePath)
        }

        // 4. Plain /destination/subfolder
        let plainPath = "/\(cleanDest)/\(subfolder)"
        if !candidates.contains(plainPath) {
            candidates.append(plainPath)
        }

        return candidates
    }

    /// Tries to list files at multiple candidate paths, returns the first that works.
    func findMediaFilesWithFallback(destination: String, title: String) async throws -> (files: [FileItem], resolvedPath: String) {
        let candidates = await candidatePaths(destination: destination, subfolder: title)

        var lastError: Error?
        for path in candidates {
            do {
                print("[FileStationService] Trying path: \(path)")
                let files = try await findMediaFiles(in: path)
                return (files, path)
            } catch {
                print("[FileStationService] Path failed: \(path) — \(error.localizedDescription)")
                lastError = error
            }
        }

        throw lastError ?? SynologyAPIError.apiError(code: 408)
    }

    /// Tries to build a streaming URL, verifying the file exists via listFiles on the parent.
    func streamingURLWithFallback(destination: String, fileName: String) async -> (url: URL?, resolvedPath: String) {
        let candidates = await candidatePaths(destination: destination, subfolder: fileName)

        // For streaming, we build the URL and verify the parent folder contains the file
        for path in candidates {
            print("[FileStationService] Trying streaming path: \(path)")
            // Check that the parent folder exists and contains the file
            let parentPath = (path as NSString).deletingLastPathComponent
            let targetName = (path as NSString).lastPathComponent
            if let files = try? await listFiles(folderPath: parentPath) {
                if files.contains(where: { $0.name == targetName }) {
                    if let url = await streamingURL(for: path) {
                        return (url, path)
                    }
                }
            }
        }

        // Fallback: just build the URL for the first candidate without verifying
        if let url = await streamingURL(for: candidates[0]) {
            return (url, candidates[0])
        }

        return (nil, candidates.first ?? "")
    }

    /// Lists files in a folder on the NAS
    func listFiles(folderPath: String) async throws -> [FileItem] {
        try await ensureFileStationSession()

        let params: [String: String] = [
            "folder_path": folderPath,
            "additional": "size",
            "sort_by": "size",
            "sort_direction": "desc"
        ]

        do {
            let response: SynologyResponse<FileListData> = try await client.apiRequest(
                api: "SYNO.FileStation.List",
                method: "list",
                version: 2,
                extraParams: params,
                useFileStationSession: true
            )
            return response.data?.files ?? []
        } catch {
            // On decode failure, fetch the raw response for debugging
            let rawResponse = try? await client.rawApiRequest(
                api: "SYNO.FileStation.List",
                method: "list",
                version: 2,
                extraParams: params,
                useFileStationSession: true
            )
            print("[FileStationService] listFiles failed for path: \(folderPath)")
            print("[FileStationService] Raw response: \(rawResponse ?? "nil")")
            throw error
        }
    }

    /// Recursively finds the first (largest) media file in a folder
    func findMediaFiles(in folderPath: String) async throws -> [FileItem] {
        let files = try await listFiles(folderPath: folderPath)
        var mediaFiles: [FileItem] = []

        for file in files {
            if file.isdir {
                // Recurse into subdirectories
                let subFiles = try await findMediaFiles(in: file.path)
                mediaFiles.append(contentsOf: subFiles)
            } else if file.isMedia {
                mediaFiles.append(file)
            }
        }

        // Sort by size descending — largest file is most likely the main content
        return mediaFiles.sorted {
            ($0.additional?.size ?? 0) > ($1.additional?.size ?? 0)
        }
    }

    /// Builds a streaming URL for a file using FileStation download API.
    /// Uses URLComponents for proper encoding of special characters in file paths.
    func streamingURL(for filePath: String) async -> URL? {
        try? await ensureFileStationSession()

        guard let config = await client.getConfig() else { return nil }

        // Get the CGI path from API discovery
        let apiPath = await client.pathForAPIPublic(api: "SYNO.FileStation.Download")
        let version = await client.clampedVersionPublic(api: "SYNO.FileStation.Download", requested: 2)

        let fsSid = await client.getFileStationSid()
        let dsSid = await client.getSid()
        let activeSid = fsSid ?? dsSid

        // Use URLComponents for proper percent-encoding
        var components = URLComponents()
        components.scheme = config.useHTTPS ? "https" : "http"
        components.host = config.address
        components.port = config.port

        // Extract path from the full API path (which includes /webapi/)
        let scheme = config.useHTTPS ? "https" : "http"
        let basePrefix = "\(scheme)://\(config.address):\(config.port)"
        if apiPath.hasPrefix(basePrefix) {
            components.path = String(apiPath.dropFirst(basePrefix.count))
        } else {
            components.path = "/webapi/entry.cgi"
        }

        var queryItems = [
            URLQueryItem(name: "api", value: "SYNO.FileStation.Download"),
            URLQueryItem(name: "method", value: "download"),
            URLQueryItem(name: "version", value: String(version)),
            URLQueryItem(name: "path", value: filePath),
            URLQueryItem(name: "mode", value: "open"),
        ]
        if let sid = activeSid {
            queryItems.append(URLQueryItem(name: "_sid", value: sid))
        }
        components.queryItems = queryItems

        let url = components.url
        print("[FileStationService] Streaming URL: \(url?.absoluteString ?? "nil")")
        return url
    }

    /// Reset session state (e.g. on logout)
    func resetSession() {
        hasFileStationSession = false
        sharedFolders = nil
    }
}
