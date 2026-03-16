import SwiftUI
import Observation

@Observable
@MainActor
final class NASInfoViewModel {
    // MARK: - Device Info (loaded once)
    var modelName: String?
    var serialNumber: String?
    var dsmVersion: String?
    var ram: Int?

    // MARK: - Live Metrics (polled)
    var uptime: Int64?
    var temperature: Int?
    var cpuUsage: Int?
    var cpuLoad1: Int?
    var cpuLoad5: Int?
    var cpuLoad15: Int?
    var memoryUsage: MemoryUtilization?
    var networkInterfaces: [NetworkUtilization] = []
    var volumes: [VolumeInfo] = []
    var disks: [DiskInfo] = []
    var connectedUsers: [ConnectionItem] = []

    // MARK: - State
    var isLoading = false
    var errorMessage: String?

    private let dsmService: DSMInfoService
    private var pollingTask: Task<Void, Never>?

    init(dsmService: DSMInfoService) {
        self.dsmService = dsmService
    }

    // MARK: - Initial Load (called once after login)

    func loadDeviceInfo() async {
        do {
            let info = try await dsmService.getSystemInfo()
            modelName = info.model
            serialNumber = info.serial
            dsmVersion = info.version_string
            ram = info.ram
            uptime = info.uptime
            temperature = info.temperature
        } catch {
            print("[NASInfo] Failed to load device info: \(error.localizedDescription)")
        }
    }

    // MARK: - Polling (for detail view)

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshMetrics()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func refreshMetrics() async {
        var errors: [String] = []

        // DSM Info — independent call
        do {
            let info = try await dsmService.getSystemInfo()
            uptime = info.uptime
            temperature = info.temperature
        } catch {
            print("[NASInfo] DSM Info error: \(error)")
            errors.append("DSM Info: \(error.localizedDescription)")
        }

        // System Utilization — independent call
        do {
            let utilization = try await dsmService.getUtilization()
            cpuUsage = utilization.cpu?.totalUsage
            cpuLoad1 = utilization.cpu?._1min_load
            cpuLoad5 = utilization.cpu?._5min_load
            cpuLoad15 = utilization.cpu?._15min_load
            memoryUsage = utilization.memory
            networkInterfaces = utilization.network ?? []
        } catch {
            print("[NASInfo] Utilization error: \(error)")
            errors.append("Utilization: \(error.localizedDescription)")
        }

        // Storage — independent call
        do {
            let storage = try await dsmService.getStorageInfo()
            volumes = storage.volumes ?? []
            disks = storage.disks ?? []
        } catch {
            print("[NASInfo] Storage error: \(error)")
            errors.append("Storage: \(error.localizedDescription)")
        }

        // Connected Users — independent call
        do {
            let connections = try await dsmService.getConnectedUsers()
            connectedUsers = connections
        } catch {
            print("[NASInfo] Connections error: \(error)")
            // Don't show as error — this API may not be available on all DSM versions
        }

        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    // MARK: - Formatted Values

    var formattedUptime: String? {
        guard let uptime, uptime > 0 else { return nil }
        let days = uptime / 86400
        let hours = (uptime % 86400) / 3600
        let minutes = (uptime % 3600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var temperatureColor: Color {
        guard let temperature else { return .secondary }
        if temperature < 50 { return .green }
        if temperature < 65 { return .yellow }
        return .red
    }
}
