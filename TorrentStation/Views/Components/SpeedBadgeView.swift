import SwiftUI

struct SpeedBadgeView: View {
    let downloadSpeed: Int64
    let uploadSpeed: Int64

    var body: some View {
        HStack(spacing: 16) {
            Label {
                Text(Formatters.formatSpeed(downloadSpeed))
                    .font(Theme.monoBody)
            } icon: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Theme.downloading)
            }

            Label {
                Text(Formatters.formatSpeed(uploadSpeed))
                    .font(Theme.monoBody)
            } icon: {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(Theme.seeding)
            }
        }
        .padding(.horizontal, Theme.paddingMedium)
        .padding(.vertical, Theme.paddingSmall)
    }
}
