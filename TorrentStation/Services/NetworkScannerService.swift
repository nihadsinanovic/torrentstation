import Foundation
import Network

/// Discovered device on the local network
struct DiscoveredDevice: Identifiable, Sendable {
    enum DeviceType: String, Sendable {
        case synology = "Synology NAS"
        case plex = "Plex Media Server"
    }

    let id: String
    let address: String
    let port: Int
    let type: DeviceType
    var name: String?

    var displayName: String {
        name ?? "\(type.rawValue) (\(address))"
    }
}

/// Scans the local network for Synology NAS and Plex Media Server instances
actor NetworkScannerService {
    private var isScanning = false

    /// Get the device's local IP address to determine the subnet
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) { // IPv4 only
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" { // Wi-Fi interfaces
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }

    /// Extract subnet prefix (e.g., "192.168.1" from "192.168.1.42")
    private func subnetPrefix(from ip: String) -> String? {
        let parts = ip.components(separatedBy: ".")
        guard parts.count == 4 else { return nil }
        return parts[0...2].joined(separator: ".")
    }

    /// Probe a single host:port with a TCP connection
    private func probe(host: String, port: Int, timeout: TimeInterval = 0.5) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                using: .tcp
            )

            let queue = DispatchQueue(label: "probe.\(host).\(port)")
            var resumed = false

            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    resumed = true
                    continuation.resume(returning: false)
                default:
                    break
                }
            }

            connection.start(queue: queue)

            // Timeout
            queue.asyncAfter(deadline: .now() + timeout) {
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
    }

    /// Try to identify a Synology NAS by probing its API
    private func identifySynology(host: String, port: Int) async -> String? {
        let scheme = port == 5001 ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host):\(port)/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query") else {
            return nil
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: config, delegate: InsecureCertDelegate(), delegateQueue: nil)

        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                // If we get a valid JSON response with "success", it's a Synology
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["success"] as? Bool == true {
                    return "Synology NAS"
                }
            }
        } catch {
            // Not a Synology
        }
        return nil
    }

    /// Try to identify a Plex server by checking its identity endpoint
    private func identifyPlex(host: String, port: Int) async -> String? {
        guard let url = URL(string: "http://\(host):\(port)/identity") else { return nil }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let container = json["MediaContainer"] as? [String: Any],
                   let name = container["friendlyName"] as? String {
                    return name
                }
                return "Plex Media Server"
            }
        } catch {
            // Not a Plex server
        }
        return nil
    }

    /// Scan the local network for devices
    func scan() async -> [DiscoveredDevice] {
        guard !isScanning else { return [] }
        isScanning = true
        defer { isScanning = false }

        guard let localIP = getLocalIPAddress(),
              let subnet = subnetPrefix(from: localIP) else {
            print("[NetworkScanner] Could not determine local IP/subnet")
            return []
        }

        print("[NetworkScanner] Scanning subnet \(subnet).0/24 from local IP \(localIP)")

        var devices: [DiscoveredDevice] = []
        let lock = NSLock()

        // Scan in parallel batches
        await withTaskGroup(of: DiscoveredDevice?.self) { group in
            for i in 1...254 {
                let host = "\(subnet).\(i)"
                if host == localIP { continue }

                // Check Synology ports (5000 HTTP, 5001 HTTPS)
                group.addTask {
                    if await self.probe(host: host, port: 5000) {
                        if let name = await self.identifySynology(host: host, port: 5000) {
                            return DiscoveredDevice(id: "\(host):5000", address: host, port: 5000, type: .synology, name: name)
                        }
                    }
                    if await self.probe(host: host, port: 5001) {
                        if let name = await self.identifySynology(host: host, port: 5001) {
                            return DiscoveredDevice(id: "\(host):5001", address: host, port: 5001, type: .synology, name: name)
                        }
                    }
                    return nil
                }

                // Check Plex port (32400)
                group.addTask {
                    if await self.probe(host: host, port: 32400) {
                        let name = await self.identifyPlex(host: host, port: 32400)
                        return DiscoveredDevice(id: "\(host):32400", address: host, port: 32400, type: .plex, name: name)
                    }
                    return nil
                }
            }

            for await device in group {
                if let device {
                    lock.lock()
                    devices.append(device)
                    lock.unlock()
                }
            }
        }

        print("[NetworkScanner] Found \(devices.count) device(s): \(devices.map { $0.displayName })")
        return devices.sorted { $0.address < $1.address }
    }
}
