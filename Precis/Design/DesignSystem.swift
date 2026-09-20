import SwiftUI

public enum PrecisDesignSystem {
    public static let paper = Color(hex: "#F3F0E8")
    public static let ink = Color(hex: "#211F1A")
    public static let marginalia = Color(hex: "#3C5A45")
    public static let flag = Color(hex: "#A8672B")
    public static let rule = Color(hex: "#D8D2C2")
    public static let surface = Color(hex: "#EAE6DA")

    public static func background(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#171613") : paper
    }

    public static func foreground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#F0EDE7") : ink
    }

    public static func surface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#1F1D1A") : surface
    }

    public static func rule(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#37342E") : rule
    }
}

public enum PrecisTypography {
    public static let title = Font.system(size: 32, weight: .semibold, design: .serif)
    public static let headline = Font.system(size: 18, weight: .semibold, design: .default)
    public static let body = Font.system(size: 15, weight: .regular, design: .default)
    public static let metadata = Font.system(size: 12, weight: .medium, design: .default)
    public static let caption = Font.system(size: 11, weight: .medium, design: .default)
}

public enum PrecisSpacing {
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = hex.map { String($0) }.joined()

        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
