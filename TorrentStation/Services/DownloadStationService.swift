import Foundation

actor DownloadStationService {
    private let client: SynologyClient

    init(client: SynologyClient) {
        self.client = client
    }

    // MARK: - Task List

    func listTasks() async throws -> [DownloadTask] {
        let response: SynologyResponse<TaskListData> = try await client.apiRequest(
            api: "SYNO.DownloadStation.Task",
            method: "list",
            version: 1,
            extraParams: [
                "additional": "transfer,detail",
                "offset": "0",
                "limit": "-1"
            ]
        )
        let rawTasks = response.data?.tasks ?? []
        return rawTasks.map { DownloadTask(from: $0) }
    }

    // MARK: - Create Task
    // Uses GET with URI parameter — POST/FormData causes error 101

    func createTask(uri: String, destination: String? = nil) async throws {
        var params = ["uri": uri]
        if let destination {
            params["destination"] = destination
        }
        print("[DownloadStation] createTask params: \(params)")
        let _: SynologyResponse<EmptyResponse> = try await client.apiRequest(
            api: "SYNO.DownloadStation.Task",
            method: "create",
            version: 1,
            extraParams: params
        )
    }

    // MARK: - Pause

    func pauseTasks(ids: [String]) async throws {
        let _: SynologyResponse<EmptyResponse> = try await client.apiRequest(
            api: "SYNO.DownloadStation.Task",
            method: "pause",
            version: 1,
            extraParams: ["id": ids.joined(separator: ",")]
        )
    }

    // MARK: - Resume

    func resumeTasks(ids: [String]) async throws {
        let _: SynologyResponse<EmptyResponse> = try await client.apiRequest(
            api: "SYNO.DownloadStation.Task",
            method: "resume",
            version: 1,
            extraParams: ["id": ids.joined(separator: ",")]
        )
    }

    // MARK: - Delete

    func deleteTasks(ids: [String], forceComplete: Bool = false) async throws {
        let _: SynologyResponse<EmptyResponse> = try await client.apiRequest(
            api: "SYNO.DownloadStation.Task",
            method: "delete",
            version: 1,
            extraParams: [
                "id": ids.joined(separator: ","),
                "force_complete": forceComplete ? "true" : "false"
            ]
        )
    }

    // MARK: - Statistics

    func getStatistics() async throws -> StatisticData {
        let response: SynologyResponse<StatisticData> = try await client.apiRequest(
            api: "SYNO.DownloadStation.Statistic",
            method: "getinfo",
            version: 1
        )
        return response.data ?? StatisticData(speed_download: 0, speed_upload: 0)
    }
}
