import Foundation
import CryptoKit

actor QuickConnectService {

    enum QuickConnectError: LocalizedError {
        case resolutionFailed
        case invalidResponse
        case noReachableServer

        var errorDescription: String? {
            switch self {
            case .resolutionFailed: "Failed to resolve QuickConnect ID"
            case .invalidResponse: "Invalid response from QuickConnect server"
            case .noReachableServer: "No reachable NAS found for this QuickConnect ID"
            }
        }
    }

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(
            configuration: config,
            delegate: InsecureCertDelegate(),
            delegateQueue: nil
        )
    }

    // MARK: - Public API

    /// Resolves a QuickConnect ID to a working ConnectionConfig.
    func resolve(quickConnectID: String) async throws -> ConnectionConfig {
        // Step 1: Get server info from Synology's global QuickConnect server
        let serverInfo = try await getServerInfo(id: quickConnectID)

        // Step 2: Build candidate URLs ordered by priority
        let candidates = buildCandidates(from: serverInfo)

        guard !candidates.isEmpty else {
            throw QuickConnectError.noReachableServer
        }

        // Step 3: Test each candidate with pingpong
        let expectedEzid = md5Hex(serverInfo.serverID ?? quickConnectID)

        for candidate in candidates {
            if await testCandidate(candidate, expectedEzid: expectedEzid) {
                return candidate
            }
        }

        // Step 4: If relay info is available, try tunnel
        if let relayConfig = try? await requestTunnel(id: quickConnectID, serverInfo: serverInfo) {
            if await testCandidate(relayConfig, expectedEzid: expectedEzid) {
                return relayConfig
            }
        }

        throw QuickConnectError.noReachableServer
    }

    // MARK: - Step 1: Get Server Info

    private func getServerInfo(id: String) async throws -> QCServerInfo {
        let url = URL(string: "https://global.quickconnect.to/Serv.php")!

        let body: [[String: Any]] = [
            [
                "version": 1,
                "command": "get_server_info",
                "stop_when_error": false,
                "stop_when_success": false,
                "id": "dsm_portal_https",
                "serverID": id,
                "is_gofile": false
            ],
            [
                "version": 1,
                "command": "get_server_info",
                "stop_when_error": false,
                "stop_when_success": false,
                "id": "dsm_portal",
                "serverID": id,
                "is_gofile": false
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)

        // Parse the response array — we take the first valid one
        guard let responses = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw QuickConnectError.invalidResponse
        }

        // Merge HTTPS and HTTP responses into a single server info
        var merged = QCServerInfo()
        for response in responses {
            merged.merge(from: response)
        }

        guard merged.serverID != nil else {
            // Check if we got an error
            if let first = responses.first, let errno = first["errno"] as? Int, errno != 0 {
                throw QuickConnectError.resolutionFailed
            }
            throw QuickConnectError.invalidResponse
        }

        return merged
    }

    // MARK: - Step 2: Build Candidates

    private func buildCandidates(from info: QCServerInfo) -> [ConnectionConfig] {
        var candidates: [ConnectionConfig] = []

        let servicePort = info.servicePort ?? 5000
        let serviceExtPort = info.serviceExtPort ?? servicePort
        let httpsPort = info.httpsPort ?? 5001
        let httpsExtPort = info.httpsExtPort ?? httpsPort

        // LAN interfaces — HTTPS first, then HTTP
        for iface in info.interfaces {
            if let ip = iface.ip, isPrivateIP(ip) {
                // HTTPS on LAN
                candidates.append(ConnectionConfig(
                    address: ip, port: httpsPort, useHTTPS: true
                ))
                // HTTP on LAN
                candidates.append(ConnectionConfig(
                    address: ip, port: servicePort, useHTTPS: false
                ))
            }
            // IPv6 LAN
            for ipv6 in iface.ipv6 where ipv6.scope == "link" {
                if let addr = ipv6.address {
                    candidates.append(ConnectionConfig(
                        address: "[\(addr)]", port: httpsPort, useHTTPS: true
                    ))
                }
            }
        }

        // FQDN
        if let fqdn = info.fqdn, !fqdn.isEmpty {
            candidates.append(ConnectionConfig(
                address: fqdn, port: httpsExtPort, useHTTPS: true
            ))
            candidates.append(ConnectionConfig(
                address: fqdn, port: serviceExtPort, useHTTPS: false
            ))
        }

        // DDNS
        if let ddns = info.ddns, !ddns.isEmpty {
            candidates.append(ConnectionConfig(
                address: ddns, port: httpsExtPort, useHTTPS: true
            ))
            candidates.append(ConnectionConfig(
                address: ddns, port: serviceExtPort, useHTTPS: false
            ))
        }

        // External IP (WAN)
        if let extIP = info.externalIP, !extIP.isEmpty {
            candidates.append(ConnectionConfig(
                address: extIP, port: httpsExtPort, useHTTPS: true
            ))
            candidates.append(ConnectionConfig(
                address: extIP, port: serviceExtPort, useHTTPS: false
            ))
        }

        return candidates
    }

    // MARK: - Step 3: Ping-Pong Test

    private func testCandidate(_ config: ConnectionConfig, expectedEzid: String) async -> Bool {
        let scheme = config.useHTTPS ? "https" : "http"
        let urlString = "\(scheme)://\(config.address):\(config.port)/webman/pingpong.cgi?action=cors&quickconnect=true"

        guard let url = URL(string: urlString) else { return false }

        // Use a short timeout for connectivity tests
        var request = URLRequest(url: url)
        request.timeoutInterval = 4

        do {
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = json["success"] as? Bool, success else {
                return false
            }

            // Verify ezid matches expected MD5 of serverID
            if let ezid = json["ezid"] as? String {
                return ezid == expectedEzid
            }

            // If no ezid in response, still accept if success is true
            return true
        } catch {
            return false
        }
    }

    // MARK: - Step 4: Tunnel Fallback

    private func requestTunnel(id: String, serverInfo: QCServerInfo) async throws -> ConnectionConfig? {
        let controlHost = serverInfo.controlHost ?? "global.quickconnect.to"
        let url = URL(string: "https://\(controlHost)/Serv.php")!

        let body: [[String: Any]] = [
            [
                "version": 1,
                "command": "request_tunnel",
                "stop_when_error": false,
                "stop_when_success": false,
                "id": "dsm_portal_https",
                "serverID": id,
                "is_gofile": false
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)

        guard let responses = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = responses.first,
              let service = first["service"] as? [String: Any] else {
            return nil
        }

        // Try relay connection
        if let relayIP = service["relay_ip"] as? String,
           let relayPort = service["relay_port"] as? Int {
            return ConnectionConfig(address: relayIP, port: relayPort, useHTTPS: true)
        }

        return nil
    }

    // MARK: - Helpers

    private func isPrivateIP(_ ip: String) -> Bool {
        ip.hasPrefix("10.") ||
        ip.hasPrefix("192.168.") ||
        ip.hasPrefix("172.16.") || ip.hasPrefix("172.17.") || ip.hasPrefix("172.18.") ||
        ip.hasPrefix("172.19.") || ip.hasPrefix("172.20.") || ip.hasPrefix("172.21.") ||
        ip.hasPrefix("172.22.") || ip.hasPrefix("172.23.") || ip.hasPrefix("172.24.") ||
        ip.hasPrefix("172.25.") || ip.hasPrefix("172.26.") || ip.hasPrefix("172.27.") ||
        ip.hasPrefix("172.28.") || ip.hasPrefix("172.29.") || ip.hasPrefix("172.30.") ||
        ip.hasPrefix("172.31.")
    }

    private func md5Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - QuickConnect Response Models

/// Parsed server info merged from HTTPS and HTTP responses
private struct QCServerInfo {
    var serverID: String?
    var controlHost: String?     // regional QC server

    // Server network info
    var interfaces: [QCInterface] = []
    var externalIP: String?
    var ddns: String?
    var fqdn: String?

    // Service ports
    var servicePort: Int?        // HTTP port (usually 5000)
    var serviceExtPort: Int?     // HTTP external port
    var httpsPort: Int?          // HTTPS port (usually 5001)
    var httpsExtPort: Int?       // HTTPS external port

    mutating func merge(from response: [String: Any]) {
        if let server = response["server"] as? [String: Any] {
            if let sid = server["serverID"] as? String { serverID = sid }
            if let d = server["ddns"] as? String, !d.isEmpty { ddns = d }
            if let f = server["fqdn"] as? String, !f.isEmpty { fqdn = f }

            if let ext = server["external"] as? [String: Any],
               let ip = ext["ip"] as? String, !ip.isEmpty {
                externalIP = ip
            }

            if let ifaces = server["interface"] as? [[String: Any]] {
                for iface in ifaces {
                    var parsed = QCInterface()
                    parsed.ip = iface["ip"] as? String
                    parsed.mask = iface["mask"] as? String
                    if let ipv6List = iface["ipv6"] as? [[String: Any]] {
                        for v6 in ipv6List {
                            parsed.ipv6.append(QCIPv6(
                                address: v6["address"] as? String,
                                scope: v6["scope"] as? String
                            ))
                        }
                    }
                    interfaces.append(parsed)
                }
            }
        }

        if let env = response["env"] as? [String: Any] {
            if let host = env["control_host"] as? String { controlHost = host }
        }

        if let service = response["service"] as? [String: Any] {
            let responseID = response["id"] as? String ?? ""
            let isHTTPS = responseID.contains("https")

            if isHTTPS {
                if let p = service["port"] as? Int { httpsPort = p }
                if let ep = service["ext_port"] as? Int, ep > 0 { httpsExtPort = ep }
            } else {
                if let p = service["port"] as? Int { servicePort = p }
                if let ep = service["ext_port"] as? Int, ep > 0 { serviceExtPort = ep }
            }
        }
    }
}

private struct QCInterface {
    var ip: String?
    var mask: String?
    var ipv6: [QCIPv6] = []
}

private struct QCIPv6 {
    var address: String?
    var scope: String?
}
