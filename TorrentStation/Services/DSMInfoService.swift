import Foundation

actor DSMInfoService {
    private let client: SynologyClient

    init(client: SynologyClient) {
        self.client = client
    }

    // MARK: - DSM Info (model, serial, DSM version, uptime, RAM, temperature)

    func getSystemInfo() async throws -> DSMInfoData {
        let response: SynologyResponse<DSMInfoData> = try await client.apiRequest(
            api: "SYNO.DSM.Info",
            method: "getinfo",
            version: 2
        )
        guard let data = response.data else {
            throw SynologyAPIError.apiError(code: 0)
        }
        return data
    }

    // MARK: - System Utilization (CPU, memory, network)

    func getUtilization() async throws -> SystemUtilizationData {
        do {
            let response: SynologyResponse<SystemUtilizationData> = try await client.apiRequest(
                api: "SYNO.Core.System.Utilization",
                method: "get",
                version: 1
            )
            guard let data = response.data else {
                throw SynologyAPIError.apiError(code: 0)
            }
            return data
        } catch {
            // Log raw response for debugging
            if let raw = try? await client.rawApiRequest(
                api: "SYNO.Core.System.Utilization", method: "get", version: 1
            ) {
                print("[DSMInfo] Raw Utilization response: \(raw.prefix(1000))")
            }
            throw error
        }
    }

    // MARK: - Connected Users

    func getConnectedUsers() async throws -> [ConnectionItem] {
        // Use manual JSON parsing for resilience
        let rawString = try await client.rawApiRequest(
            api: "SYNO.Core.CurrentConnection",
            method: "list",
            version: 1
        )

        guard let rawData = rawString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              let success = json["success"] as? Bool, success,
              let data = json["data"] as? [String: Any],
              let items = data["items"] as? [[String: Any]] else {
            return []
        }

        var connections: [ConnectionItem] = []
        for item in items {
            if let itemData = try? JSONSerialization.data(withJSONObject: item),
               let conn = try? JSONDecoder().decode(ConnectionItem.self, from: itemData) {
                connections.append(conn)
            }
        }
        return connections
    }

    // MARK: - Storage Info (volumes, disks)

    func getStorageInfo() async throws -> StorageData {
        // Fetch raw JSON first, then manually extract volumes and disks
        let rawString = try await client.rawApiRequest(
            api: "SYNO.Storage.CGI.Storage",
            method: "load_info",
            version: 1
        )

        guard let rawData = rawString.data(using: .utf8) else {
            throw SynologyAPIError.decodingError(
                DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Non-UTF8 response"))
            )
        }

        guard let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              let success = json["success"] as? Bool, success,
              let data = json["data"] as? [String: Any] else {
            print("[DSMInfo] Storage: API returned failure or unexpected shape. Raw: \(rawString.prefix(500))")
            throw SynologyAPIError.apiError(code: 0)
        }

        // Decode volumes
        var volumes: [VolumeInfo] = []
        if let volumesArray = data["volumes"] as? [[String: Any]] {
            for volDict in volumesArray {
                if let volData = try? JSONSerialization.data(withJSONObject: volDict),
                   let vol = try? JSONDecoder().decode(VolumeInfo.self, from: volData) {
                    volumes.append(vol)
                } else {
                    print("[DSMInfo] Failed to decode volume: \(volDict.keys.sorted())")
                }
            }
        }

        // Decode disks
        var disks: [DiskInfo] = []
        if let disksArray = data["disks"] as? [[String: Any]] {
            for diskDict in disksArray {
                if let diskData = try? JSONSerialization.data(withJSONObject: diskDict),
                   let disk = try? JSONDecoder().decode(DiskInfo.self, from: diskData) {
                    disks.append(disk)
                } else {
                    print("[DSMInfo] Failed to decode disk: \(diskDict.keys.sorted())")
                }
            }
        }

        return StorageData(volumes: volumes, disks: disks)
    }
}
