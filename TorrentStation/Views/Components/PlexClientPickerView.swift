import SwiftUI

struct PlexClientPickerView: View {
    let clients: [PlexResource]
    let taskTitle: String
    let onSelect: (PlexResource) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(clients) { client in
                Button {
                    onSelect(client)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: iconName(for: client))
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(client.name)
                                .font(.headline)
                            if let product = client.product {
                                Text(product)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Play on\u{2026}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func iconName(for client: PlexResource) -> String {
        let product = (client.product ?? "").lowercased()
        if product.contains("apple tv") || product.contains("tvos") {
            return "appletv.fill"
        } else if product.contains("iphone") || product.contains("ios") {
            return "iphone"
        } else if product.contains("ipad") {
            return "ipad"
        } else if product.contains("mac") || product.contains("macos") {
            return "desktopcomputer"
        } else if product.contains("android") {
            return "smartphone"
        } else if product.contains("web") || product.contains("chrome") {
            return "globe"
        }
        return "play.display"
    }
}
