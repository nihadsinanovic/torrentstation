import SwiftUI

enum Theme {
    // MARK: - Colors
    static let accent = Color(hex: 0x00D4AA)
    static let accentDark = Color(hex: 0x00B894)
    static let downloading = Color.blue
    static let seeding = Color.green
    static let paused = Color.orange
    static let completed = Color(hex: 0x00D4AA)
    static let error = Color.red
    static let waiting = Color.yellow

    // MARK: - Fonts
    static let monoCaption = Font.system(.caption, design: .monospaced)
    static let monoBody = Font.system(.body, design: .monospaced)
    static let monoTitle3 = Font.system(.title3, design: .monospaced, weight: .semibold)

    // MARK: - Spacing
    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 16
    static let paddingLarge: CGFloat = 24
    static let cornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 20
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
