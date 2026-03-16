import Foundation

enum Formatters {
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }

    static func formatSpeed(_ bytesPerSecond: Int64) -> String {
        if bytesPerSecond <= 0 { return "0 B/s" }
        return formatBytes(bytesPerSecond) + "/s"
    }

    static func formatEta(seconds: Int64) -> String {
        if seconds <= 0 { return "---" }
        if seconds < 60 { return "< 1m" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func formatProgress(_ ratio: Double) -> String {
        String(format: "%.1f%%", ratio * 100)
    }
}
