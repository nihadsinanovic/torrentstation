import Foundation

// MARK: - Constants

enum ShareConstants {
    static let appGroupID = "group.frugi.torrentstation.shared"
}

// MARK: - Credentials Helper (reads from shared App Group UserDefaults)

enum ShareCredentialsHelper {

    static func loadCredentials() -> ShareStoredCredentials? {
        guard let defaults = UserDefaults(suiteName: ShareConstants.appGroupID),
              let data = defaults.data(forKey: "credentials") else {
            return nil
        }
        return try? JSONDecoder().decode(ShareStoredCredentials.self, from: data)
    }
}

// MARK: - Credential Models (mirroring main app's StoredCredentials & ConnectionConfig)

struct ShareStoredCredentials: Codable {
    let config: ShareConnectionConfig
    let username: String
    let password: String
}

struct ShareConnectionConfig: Codable {
    let address: String
    let port: Int
    let useHTTPS: Bool
    let quickConnectID: String?

    var baseURL: String {
        let scheme = useHTTPS ? "https" : "http"
        return "\(scheme)://\(address):\(port)/webapi"
    }
}

// MARK: - Lightweight NAS Client

enum ShareNASClient {

    enum ShareError: LocalizedError {
        case notLoggedIn
        case loginFailed
        case createTaskFailed(String)
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .notLoggedIn: "Not logged in. Open TorrentStation and connect to your NAS."
            case .loginFailed: "Failed to authenticate with NAS."
            case .createTaskFailed(let msg): "Failed to create download: \(msg)"
            case .networkError(let msg): "Network error: \(msg)"
            }
        }
    }

    /// Creates a download task on the NAS.
    static func createDownload(uri: String, destination: String?) async throws {
        guard let creds = ShareCredentialsHelper.loadCredentials() else {
            throw ShareError.notLoggedIn
        }

        let session = URLSession(
            configuration: .default,
            delegate: ShareCertDelegate(),
            delegateQueue: nil
        )

        // Step 1: Discover APIs
        let apiMapURL = "\(creds.config.baseURL)/query.cgi?api=SYNO.API.Info&version=1&method=query&query=all"
        let apiMap = try await fetchAPIMap(session: session, urlString: apiMapURL)

        // Step 2: Login to get SID
        let authPath = apiMap["SYNO.API.Auth"] ?? "entry.cgi"
        let sid = try await login(
            session: session,
            baseURL: creds.config.baseURL,
            path: authPath,
            username: creds.username,
            password: creds.password
        )

        // Step 3: Create download task
        let taskPath = apiMap["SYNO.DownloadStation.Task"] ?? "entry.cgi"
        try await createTask(
            session: session,
            baseURL: creds.config.baseURL,
            path: taskPath,
            sid: sid,
            uri: uri,
            destination: destination
        )

        // Step 4: Logout (best effort)
        try? await logout(session: session, baseURL: creds.config.baseURL, path: authPath, sid: sid)
    }

    // MARK: - API Discovery

    private static func fetchAPIMap(session: URLSession, urlString: String) async throws -> [String: String] {
        guard let url = URL(string: urlString) else { throw ShareError.networkError("Invalid URL") }

        let (data, _) = try await session.data(from: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? Bool, success,
              let apiData = json["data"] as? [String: [String: Any]] else {
            return [:]
        }

        var map: [String: String] = [:]
        for (apiName, info) in apiData {
            if let path = info["path"] as? String {
                map[apiName] = path
            }
        }
        return map
    }

    // MARK: - Login

    private static func login(
        session: URLSession,
        baseURL: String,
        path: String,
        username: String,
        password: String
    ) async throws -> String {
        let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        let encodedPass = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password

        let urlString = "\(baseURL)/\(path)?api=SYNO.API.Auth&method=login&version=6&account=\(encodedUser)&passwd=\(encodedPass)&session=DownloadStation&format=sid"
        guard let url = URL(string: urlString) else { throw ShareError.loginFailed }

        let (data, _) = try await session.data(from: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? Bool, success,
              let responseData = json["data"] as? [String: Any],
              let sid = responseData["sid"] as? String else {
            throw ShareError.loginFailed
        }

        return sid
    }

    // MARK: - Create Task

    private static func createTask(
        session: URLSession,
        baseURL: String,
        path: String,
        sid: String,
        uri: String,
        destination: String?
    ) async throws {
        // Build query parameters — need careful encoding for magnet URIs
        var paramParts = [
            "api=SYNO.DownloadStation.Task",
            "method=create",
            "version=1",
            "_sid=\(sid)"
        ]

        // URI needs special encoding — magnet links contain & characters
        let allowedChars: CharacterSet = {
            var set = CharacterSet.urlQueryAllowed
            set.remove(charactersIn: "&=+")
            return set
        }()
        let encodedURI = uri.addingPercentEncoding(withAllowedCharacters: allowedChars) ?? uri
        paramParts.append("uri=\(encodedURI)")

        if let dest = destination {
            let encodedDest = dest.addingPercentEncoding(withAllowedCharacters: allowedChars) ?? dest
            paramParts.append("destination=\(encodedDest)")
        }

        let urlString = "\(baseURL)/\(path)?\(paramParts.joined(separator: "&"))"
        guard let url = URL(string: urlString) else {
            throw ShareError.createTaskFailed("Invalid URL")
        }

        let (data, _) = try await session.data(from: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? Bool else {
            throw ShareError.createTaskFailed("Invalid response")
        }

        if !success {
            let errorCode = (json["error"] as? [String: Any])?["code"] as? Int ?? 0
            throw ShareError.createTaskFailed("Error code \(errorCode)")
        }
    }

    // MARK: - Logout

    private static func logout(
        session: URLSession,
        baseURL: String,
        path: String,
        sid: String
    ) async throws {
        let urlString = "\(baseURL)/\(path)?api=SYNO.API.Auth&method=logout&version=1&session=DownloadStation&_sid=\(sid)"
        guard let url = URL(string: urlString) else { return }
        _ = try? await session.data(from: url)
    }
}

// MARK: - Self-Signed Certificate Support

final class ShareCertDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}
