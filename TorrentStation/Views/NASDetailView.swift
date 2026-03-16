import SwiftUI

struct NASDetailView: View {
    var viewModel: NASInfoViewModel

    var body: some View {
        List {
            // MARK: - Device Info
            Section("Device") {
                if let model = viewModel.modelName {
                    infoRow(icon: "externaldrive.fill", label: "Model", value: model)
                }
                if let serial = viewModel.serialNumber {
                    infoRow(icon: "number", label: "Serial", value: serial)
                }
                if let dsm = viewModel.dsmVersion {
                    infoRow(icon: "gearshape.2.fill", label: "DSM", value: dsm)
                }
                if let ram = viewModel.ram {
                    infoRow(icon: "memorychip", label: "RAM", value: "\(ram) MB")
                }
                if let uptime = viewModel.formattedUptime {
                    infoRow(icon: "clock.fill", label: "Uptime", value: uptime)
                }
            }

            // MARK: - System Metrics
            Section("System") {
                // CPU
                if let cpu = viewModel.cpuUsage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24)
                            Text("CPU Usage")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(cpu)%")
                                .font(Theme.monoCaption)
                        }
                        ProgressView(value: Double(cpu), total: 100)
                            .tint(cpuColor(cpu))
                    }
                }

                // CPU Load Averages
                if viewModel.cpuLoad1 != nil || viewModel.cpuLoad5 != nil || viewModel.cpuLoad15 != nil {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                        Text("Load Avg")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.cpuLoad1 ?? 0)%  \(viewModel.cpuLoad5 ?? 0)%  \(viewModel.cpuLoad15 ?? 0)%")
                            .font(Theme.monoCaption)
                        Text("1m / 5m / 15m")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Memory
                if let mem = viewModel.memoryUsage, let total = mem.total_real, total > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "memorychip")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24)
                            Text("Memory")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Formatters.formatBytes(mem.usedReal * 1024)) / \(Formatters.formatBytes(total * 1024))")
                                .font(Theme.monoCaption)
                        }
                        ProgressView(value: mem.usagePercent, total: 100)
                            .tint(memoryColor(mem.usagePercent))
                    }
                }

                // Swap
                if let mem = viewModel.memoryUsage, mem.hasSwap {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.triangle.swap")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24)
                            Text("Swap")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Formatters.formatBytes(mem.usedSwap * 1024)) / \(Formatters.formatBytes((mem.total_swap ?? 0) * 1024))")
                                .font(Theme.monoCaption)
                        }
                        ProgressView(value: mem.swapPercent, total: 100)
                            .tint(memoryColor(mem.swapPercent))
                    }
                }

                // Temperature
                if let temp = viewModel.temperature {
                    HStack {
                        Image(systemName: "thermometer.medium")
                            .foregroundStyle(viewModel.temperatureColor)
                            .frame(width: 24)
                        Text("Temperature")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(temp)\u{00B0}C")
                            .font(Theme.monoCaption)
                            .foregroundStyle(viewModel.temperatureColor)
                    }
                }
            }

            // MARK: - Storage Volumes
            if !viewModel.volumes.isEmpty {
                Section("Volumes") {
                    ForEach(viewModel.volumes) { volume in
                        volumeRow(volume)
                    }
                }
            }

            // MARK: - Disks
            if !viewModel.disks.isEmpty {
                Section("Disks") {
                    ForEach(viewModel.disks) { disk in
                        diskRow(disk)
                    }
                }
            }

            // MARK: - Network
            let activeInterfaces = viewModel.networkInterfaces.filter {
                ($0.rx ?? 0) > 0 || ($0.tx ?? 0) > 0 || $0.device == "total"
            }
            if !activeInterfaces.isEmpty {
                Section("Network") {
                    ForEach(activeInterfaces, id: \.device) { iface in
                        networkRow(iface)
                    }
                }
            }

            // MARK: - Connected Users
            if !viewModel.connectedUsers.isEmpty {
                Section("Connected Users") {
                    ForEach(viewModel.connectedUsers) { conn in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conn.who ?? "Unknown")
                                    .font(.subheadline.weight(.medium))
                                if let from = conn.from {
                                    Text(from)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let type = conn.type {
                                Text(type)
                                    .font(Theme.monoCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // MARK: - Error
            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(viewModel.modelName ?? "NAS")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    // MARK: - Row Builders

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Theme.monoCaption)
        }
    }

    @ViewBuilder
    private func volumeRow(_ volume: VolumeInfo) -> some View {
        if let size = volume.size {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(volume.display_name ?? volume.vol_path ?? "Volume")
                            .font(.subheadline.weight(.medium))
                        // RAID type + filesystem
                        let details = [volume.device_type?.uppercased(), volume.fs_type]
                            .compactMap { $0 }
                        if !details.isEmpty {
                            Text(details.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let status = volume.status {
                        Text(status.capitalized)
                            .font(.caption)
                            .foregroundStyle(status == "normal" ? .green : .orange)
                    }
                }

                ProgressView(value: size.usagePercent, total: 100)
                    .tint(storageColor(size.usagePercent))

                HStack {
                    Text("Used: \(Formatters.formatBytes(size.usedBytes))")
                        .font(Theme.monoCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Free: \(Formatters.formatBytes(size.freeBytes))")
                        .font(Theme.monoCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Total: \(Formatters.formatBytes(size.totalBytes))")
                        .font(Theme.monoCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func diskRow(_ disk: DiskInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "opticaldiscdrive.fill")
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(disk.name ?? "Disk")
                        .font(.subheadline.weight(.medium))
                    if let model = disk.model {
                        Text(model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let firm = disk.firm, !firm.isEmpty {
                        Text("FW: \(firm)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if let status = disk.status {
                    Text(status.capitalized)
                        .font(.caption)
                        .foregroundStyle(status == "normal" ? .green : .orange)
                }
            }

            HStack {
                if disk.sizeBytes > 0 {
                    Text(Formatters.formatBytes(disk.sizeBytes))
                        .font(Theme.monoCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let temp = disk.temp {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.medium")
                            .font(.caption2)
                        Text("\(temp)\u{00B0}C")
                            .font(Theme.monoCaption)
                    }
                    .foregroundStyle(diskTempColor(temp))
                }
                if let smart = disk.smart_status {
                    Text("SMART: \(smart.capitalized)")
                        .font(Theme.monoCaption)
                        .foregroundStyle(smart == "normal" ? .green : .orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func networkRow(_ iface: NetworkUtilization) -> some View {
        HStack {
            Image(systemName: "network")
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(iface.device ?? "Interface")
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                        .foregroundStyle(Theme.downloading)
                    Text(Formatters.formatSpeed(iface.rx ?? 0))
                        .font(Theme.monoCaption)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption2)
                        .foregroundStyle(Theme.seeding)
                    Text(Formatters.formatSpeed(iface.tx ?? 0))
                        .font(Theme.monoCaption)
                }
            }
        }
    }

    // MARK: - Color Helpers

    private func cpuColor(_ percent: Int) -> Color {
        if percent < 50 { return .green }
        if percent < 80 { return .yellow }
        return .red
    }

    private func memoryColor(_ percent: Double) -> Color {
        if percent < 60 { return .green }
        if percent < 85 { return .yellow }
        return .red
    }

    private func storageColor(_ percent: Double) -> Color {
        if percent < 70 { return Theme.accent }
        if percent < 90 { return .yellow }
        return .red
    }

    private func diskTempColor(_ temp: Int) -> Color {
        if temp < 45 { return .green }
        if temp < 55 { return .yellow }
        return .red
    }
}
