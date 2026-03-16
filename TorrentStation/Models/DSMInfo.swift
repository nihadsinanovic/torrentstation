import Foundation

// MARK: - SYNO.DSM.Info Response

nonisolated struct DSMInfoData: Decodable, Sendable {
    let model: String?
    let serial: String?
    let version_string: String?  // e.g. "DSM 7.2-64570 Update 3"
    let uptime: Int64?           // seconds
    let ram: Int?                // MB
    let temperature: Int?        // Celsius
}

// MARK: - SYNO.Core.System.Utilization Response

nonisolated struct SystemUtilizationData: Decodable, Sendable {
    let cpu: CPUUtilization?
    let memory: MemoryUtilization?
    let network: [NetworkUtilization]?
}

nonisolated struct CPUUtilization: Decodable, Sendable {
    // Synology API uses *_load suffixed field names
    let user_load: Int?
    let system_load: Int?
    let other_load: Int?

    // Load averages
    let _1min_load: Int?    // JSON key "1min_load" — mapped via CodingKeys
    let _5min_load: Int?    // JSON key "5min_load"
    let _15min_load: Int?   // JSON key "15min_load"

    var totalUsage: Int {
        (user_load ?? 0) + (system_load ?? 0) + (other_load ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case user_load, system_load, other_load
        case _1min_load = "1min_load"
        case _5min_load = "5min_load"
        case _15min_load = "15min_load"
    }
}

nonisolated struct MemoryUtilization: Decodable, Sendable {
    let memory_size: Int64?   // total physical RAM in MB
    let real_usage: Double?   // percentage (0-100) of real memory used
    let total_real: Int64?    // KB
    let avail_real: Int64?    // KB
    let total_swap: Int64?    // KB
    let avail_swap: Int64?    // KB
    let cached: Int64?        // KB
    let buffer: Int64?        // KB
    let si_disk: Int64?
    let so_disk: Int64?
    let swap_usage: Double?

    var usedReal: Int64 {
        (total_real ?? 0) - (avail_real ?? 0)
    }

    var usagePercent: Double {
        // Prefer the direct percentage field from the API
        if let usage = real_usage { return usage }
        guard let total = total_real, total > 0 else { return 0 }
        return Double(usedReal) / Double(total) * 100
    }

    var usedSwap: Int64 {
        (total_swap ?? 0) - (avail_swap ?? 0)
    }

    var swapPercent: Double {
        if let usage = swap_usage { return usage }
        guard let total = total_swap, total > 0 else { return 0 }
        return Double(usedSwap) / Double(total) * 100
    }

    var hasSwap: Bool {
        (total_swap ?? 0) > 0
    }
}

nonisolated struct NetworkUtilization: Decodable, Sendable {
    let device: String?
    let rx: Int64?   // bytes/sec receive
    let tx: Int64?   // bytes/sec transmit
}

// MARK: - SYNO.Storage.CGI.Storage Response

nonisolated struct StorageData: Sendable {
    let volumes: [VolumeInfo]?
    let disks: [DiskInfo]?
}

nonisolated struct VolumeInfo: Decodable, Identifiable, Sendable {
    let id: String?
    let status: String?
    let vol_path: String?
    let display_name: String?
    let device_type: String?
    let fs_type: String?
    let size: VolumeSize?

    var volumeID: String { id ?? vol_path ?? UUID().uuidString }

    nonisolated var identifier: String { volumeID }
}

nonisolated struct VolumeSize: Decodable, Sendable {
    let total: VolumeSizeValue?
    let used: VolumeSizeValue?

    var totalBytes: Int64 { total?.int64Value ?? 0 }
    var usedBytes: Int64 { used?.int64Value ?? 0 }
    var freeBytes: Int64 { totalBytes - usedBytes }

    var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
}

/// Handles Synology returning size values as either String or Int64
nonisolated struct VolumeSizeValue: Decodable, Sendable {
    let int64Value: Int64

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringVal = try? container.decode(String.self) {
            int64Value = Int64(stringVal) ?? 0
        } else if let intVal = try? container.decode(Int64.self) {
            int64Value = intVal
        } else if let intVal = try? container.decode(Int.self) {
            int64Value = Int64(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            int64Value = Int64(doubleVal)
        } else {
            int64Value = 0
        }
    }
}

nonisolated struct DiskInfo: Decodable, Identifiable, Sendable {
    let id: String?
    let name: String?
    let model: String?
    let serial: String?
    let vendor: String?
    let status: String?           // "normal", "warning", etc.
    let temp: Int?                // Celsius
    let size_total: VolumeSizeValue?  // bytes — can be String or Int64
    let smart_status: String?     // "normal", etc.
    let diskType: String?
    let firm: String?             // firmware version

    var sizeBytes: Int64 { size_total?.int64Value ?? 0 }
    var diskID: String { id ?? name ?? UUID().uuidString }

    nonisolated var identifier: String { diskID }
}

// MARK: - SYNO.Core.CurrentConnection Response

nonisolated struct CurrentConnectionData: Decodable, Sendable {
    let items: [ConnectionItem]?

    enum CodingKeys: String, CodingKey {
        case items
    }
}

nonisolated struct ConnectionItem: Decodable, Identifiable, Sendable {
    let who: String?        // username
    let from: String?       // IP address
    let type: String?       // "CIFS", "AFP", "FTP", "DSM", etc.
    let time: Int64?        // connection time (epoch)

    var id: String { "\(who ?? "")-\(from ?? "")-\(type ?? "")" }
}

// MARK: - Aggregated NAS System Info

nonisolated struct NASSystemInfo: Sendable {
    let model: String
    let serial: String
    let dsmVersion: String
    let uptime: Int64         // seconds
    let ram: Int              // MB
    let temperature: Int      // Celsius
}
