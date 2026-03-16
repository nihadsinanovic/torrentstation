import Foundation

nonisolated struct ConnectionConfig: Codable, Equatable, Sendable {
    var address: String
    var port: Int
    var useHTTPS: Bool
    var quickConnectID: String?

    var baseURL: String {
        let scheme = useHTTPS ? "https" : "http"
        return "\(scheme)://\(address):\(port)/webapi"
    }

    var isQuickConnect: Bool {
        quickConnectID != nil && !quickConnectID!.isEmpty
    }
}
