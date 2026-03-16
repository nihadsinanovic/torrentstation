import SwiftUI

struct ProgressBarView: View {
    let progress: Double
    let status: TaskStatus

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))

                RoundedRectangle(cornerRadius: 4)
                    .fill(colorForStatus(status).gradient)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 6)
    }

    private func colorForStatus(_ status: TaskStatus) -> Color {
        switch status {
        case .downloading, .hashChecking, .extracting, .fileHostingWaiting, .waiting, .unknown:
            Theme.downloading
        case .seeding: Theme.seeding
        case .paused: Theme.paused
        case .finished: Theme.completed
        case .error: Theme.error
        }
    }
}
