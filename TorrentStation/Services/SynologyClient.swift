import Foundation

actor SynologyClient {
    private var config: ConnectionConfig?
    private var sid: String?
    private var fileStationSid: String?
    private var apiMap: [String: APIInfo] = [:]
    private let session: URLSession

    // Custom character set that excludes & = + from URL query allowed chars
    // Critical for magnet links which contain & characters
    private static let paramValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+")
        return set
    }()

    init() {
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = 15
        urlConfig.timeoutIntervalForResource = 30
        self.session = URLSession(
            configuration: urlConfig,
            delegate: InsecureCertDelegate(),
            delegateQueue: nil
        )
    }

    // MARK: - Configuration

    func configure(config: ConnectionConfig) {
        self.config = config
        self.apiMap = [:]
        self.fileStationSid = nil
    }

    func setSid(_ sid: String?) {
        self.sid = sid
    }

    func setFileStationSid(_ sid: String?) {
        self.fileStationSid = sid
    }

    func getSid() -> String? { sid }
    func getFileStationSid() -> String? { fileStationSid }
    func getConfig() -> ConnectionConfig? { config }

    /// Builds a raw URL string for an API call (for streaming — not decoded as JSON)
    func buildURL(api: String, method: String, version: Int, extraParams: [String: String] = [:], useFileStationSession: Bool = false) -> String? {
        let path = pathForAPI(api)
        let ver = clampedVersion(api: api, requested: version)
        var params: [String: String] = [
            "api": api,
            "method": method,
            "version": String(ver)
        ]
        let activeSid = useFileStationSession ? (fileStationSid ?? sid) : sid
        if let activeSid {
            params["_sid"] = activeSid
        }
        for (k, v) in extraParams {
            params[k] = v
        }
        let queryString = params
            .map { key, value in
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: Self.paramValueAllowed) ?? value
                return "\(key)=\(encodedValue)"
            }
            .joined(separator: "&")
        return "\(path)?\(queryString)"
    }

    // MARK: - API Discovery

    func discoverAPIs() async throws {
        guard let config else { throw SynologyAPIError.invalidURL }
        let url = "\(config.baseURL)/query.cgi?api=SYNO.API.Info&version=1&method=query&query=all"
        let response: SynologyResponse<[String: APIInfo]> = try await performRequest(urlString: url)
        if let data = response.data {
            self.apiMap = data
        }
    }

    // MARK: - Path Resolution

    private func pathForAPI(_ apiName: String) -> String {
        guard let config else { return "" }
        if let info = apiMap[apiName] {
            return "\(config.baseURL)/\(info.path)"
        }
        return "\(config.baseURL)/entry.cgi"
    }

    /// Public accessor for path resolution (used by FileStationService for URL building)
    func pathForAPIPublic(api: String) -> String {
        pathForAPI(api)
    }

    private func clampedVersion(api: String, requested: Int) -> Int {
        guard let info = apiMap[api] else { return requested }
        return min(requested, info.maxVersion)
    }

    /// Public accessor for version clamping
    func clampedVersionPublic(api: String, requested: Int) -> Int {
        clampedVersion(api: api, requested: requested)
    }

    // MARK: - Request Execution

    private func performRequest<T: Decodable>(urlString: String) async throws -> SynologyResponse<T> {
        guard let url = URL(string: urlString) else {
            throw SynologyAPIError.invalidURL
        }
        var responseData = Data()
        do {
            let (data, httpResponse) = try await session.data(from: url)
            responseData = data
            if let http = httpResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw SynologyAPIError.httpError(statusCode: http.statusCode)
            }
            let decoded = try JSONDecoder().decode(SynologyResponse<T>.self, from: data)
            if !decoded.success, let err = decoded.error {
                throw SynologyAPIError.apiError(code: err.code)
            }
            return decoded
        } catch let error as SynologyAPIError {
            throw error
        } catch let error as DecodingError {
            let preview = String(data: responseData, encoding: .utf8)?.prefix(500) ?? "non-utf8"
            print("[SynologyClient] Decode error for \(T.self): \(error)")
            print("[SynologyClient] Response preview: \(preview)")
            throw SynologyAPIError.decodingError(error)
        } catch {
            throw SynologyAPIError.connectionFailed(error)
        }
    }

    /// Performs a raw API request and returns the response data as a string (for debugging)
    func rawApiRequest(
        api: String,
        method: String,
        version: Int,
        extraParams: [String: String] = [:],
        useFileStationSession: Bool = false
    ) async throws -> String {
        let path = pathForAPI(api)
        let ver = clampedVersion(api: api, requested: version)
        var params: [String: String] = [
            "api": api,
            "method": method,
            "version": String(ver)
        ]
        let activeSid = useFileStationSession ? (fileStationSid ?? sid) : sid
        if let activeSid {
            params["_sid"] = activeSid
        }
        for (k, v) in extraParams {
            params[k] = v
        }
        let queryString = params
            .map { key, value in
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: Self.paramValueAllowed) ?? value
                return "\(key)=\(encodedValue)"
            }
            .joined(separator: "&")
        let urlString = "\(path)?\(queryString)"
        guard let url = URL(string: urlString) else {
            throw SynologyAPIError.invalidURL
        }
        let (data, _) = try await session.data(from: url)
        return String(data: data, encoding: .utf8) ?? "non-utf8 response"
    }

    func apiRequest<T: Decodable>(
        api: String,
        method: String,
        version: Int,
        extraParams: [String: String] = [:],
        useFileStationSession: Bool = false
    ) async throws -> SynologyResponse<T> {
        let path = pathForAPI(api)
        let ver = clampedVersion(api: api, requested: version)
        var params: [String: String] = [
            "api": api,
            "method": method,
            "version": String(ver)
        ]
        let activeSid = useFileStationSession ? (fileStationSid ?? sid) : sid
        if let activeSid {
            params["_sid"] = activeSid
        }
        for (k, v) in extraParams {
            params[k] = v
        }
        let queryString = params
            .map { key, value in
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: Self.paramValueAllowed) ?? value
                return "\(key)=\(encodedValue)"
            }
            .joined(separator: "&")
        let urlString = "\(path)?\(queryString)"
        return try await performRequest(urlString: urlString)
    }
}

// MARK: - Self-Signed Certificate Support

final class InsecureCertDelegate: NSObject, URLSessionDelegate, Sendable {
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
