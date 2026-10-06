import SwiftUI
import AppKit

enum PrecisTheme: String, CaseIterable, Identifiable {
    case standard
    case modernLight
    case neoLight
    case dark

    static let storageKey = "colorTheme"

    static var current: PrecisTheme {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey) else { return .standard }
        return PrecisTheme(rawValue: rawValue) ?? .standard
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .standard: "Standard Light"
        case .modernLight: "Modern Light"
        case .neoLight: "Neo Light"
        case .dark: "Dark"
        }
    }

    var detail: String {
        switch self {
        case .standard: "Paper, ink, and forest green"
        case .modernLight: "Cool surfaces and clear blue accents"
        case .neoLight: "True neutral grays and vivid indigo"
        case .dark: "Charcoal surfaces with soft teal accents"
        }
    }

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }

    var paper: Color {
        switch self {
        case .standard: Color(hex: "#F3F0E8")
        case .modernLight: Color(hex: "#F4F7FA")
        case .neoLight: Color(hex: "#F5F5F7")
        case .dark: Color(hex: "#222930")
        }
    }

    var background: Color {
        switch self {
        case .standard: Color(hex: "#FFFFFF")
        case .modernLight: Color(hex: "#F4F7FA")
        case .neoLight: Color(hex: "#FAFAFA")
        case .dark: Color(hex: "#171C21")
        }
    }

    var foreground: Color {
        switch self {
        case .standard: Color(hex: "#211F1A")
        case .modernLight: Color(hex: "#1C2732")
        case .neoLight: Color(hex: "#17181C")
        case .dark: Color(hex: "#E8EDF1")
        }
    }

    var surface: Color {
        switch self {
        case .standard: Color(hex: "#EAE6DA")
        case .modernLight: Color(hex: "#FFFFFF")
        case .neoLight: Color(hex: "#FFFFFF")
        case .dark: Color(hex: "#222930")
        }
    }

    /// Left-sidebar backdrop. Light gray in the light themes so the sidebar
    /// reads as a column of its own beside the white reading panes; the dark
    /// theme keeps the surface tone it always had.
    var sidebar: Color {
        switch self {
        case .standard: Color(hex: "#EFEDE7")
        case .modernLight: Color(hex: "#E9EDF2")
        case .neoLight: Color(hex: "#EFEFF1")
        case .dark: Color(hex: "#222930")
        }
    }

    var rule: Color {
        switch self {
        case .standard: Color(hex: "#D8D2C2")
        case .modernLight: Color(hex: "#D9E1E8")
        case .neoLight: Color(hex: "#E2E2E7")
        case .dark: Color(hex: "#38434D")
        }
    }

    var accent: Color {
        switch self {
        case .standard: Color(hex: "#3C5A45")
        case .modernLight: Color(hex: "#176B87")
        case .neoLight: Color(hex: "#4F46E5")
        case .dark: Color(hex: "#67B6A5")
        }
    }

    var flag: Color {
        switch self {
        case .standard: Color(hex: "#A8672B")
        case .modernLight: Color(hex: "#B45B37")
        case .neoLight: Color(hex: "#E11D48")
        case .dark: Color(hex: "#E7AB65")
        }
    }
}

public enum PrecisDesignSystem {
    public static var paper: Color { PrecisTheme.current.paper }
    public static var ink: Color { PrecisTheme.current.foreground }
    public static var marginalia: Color { PrecisTheme.current.accent }
    public static var flag: Color { PrecisTheme.current.flag }
    public static var rule: Color { PrecisTheme.current.rule }
    public static var surface: Color { PrecisTheme.current.surface }

    public static func background(for _: ColorScheme) -> Color {
        PrecisTheme.current.background
    }

    public static func foreground(for _: ColorScheme) -> Color {
        PrecisTheme.current.foreground
    }

    public static func surface(for _: ColorScheme) -> Color {
        PrecisTheme.current.surface
    }

    public static func sidebar(for _: ColorScheme) -> Color {
        PrecisTheme.current.sidebar
    }

    public static func rule(for _: ColorScheme) -> Color {
        PrecisTheme.current.rule
    }

    // MARK: - Persisted tints (category text/icon colors)

    /// Reads a "#RRGGBB"/"RRGGBB" hex string; nil for malformed input.
    public static func color(hex: String) -> Color? {
        let digits = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard digits.count == 6, let value = UInt64(digits, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    /// "#RRGGBB" for any Color — the storage inverse of `color(hex:)`.
    public static func hexString(from color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(
            format: "#%02X%02X%02X",
            Int((nsColor.redComponent * 255).rounded()),
            Int((nsColor.greenComponent * 255).rounded()),
            Int((nsColor.blueComponent * 255).rounded())
        )
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
