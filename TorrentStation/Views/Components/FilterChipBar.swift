import SwiftUI

struct FilterChipBar: View {
    @Binding var selectedFilter: TaskFilter
    let counts: [TaskFilter: Int]
    @Namespace private var chipNamespace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskFilter.allCases) { filter in
                    FilterChip(
                        title: filter.displayName,
                        count: counts[filter] ?? 0,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.snappy) {
                            selectedFilter = filter
                        }
                    }
                    .glassEffect(
                        selectedFilter == filter
                            ? .regular.tint(Theme.accent).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
                    .glassEffectID(filter.rawValue, in: chipNamespace)
                }
            }
            .padding(.horizontal, Theme.paddingMedium)
        }
        .frame(height: 44)
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            isSelected ? Theme.accent.opacity(0.3) : Color(.systemGray5),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
