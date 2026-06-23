import SwiftUI
import UIKit

/// Warm monochrome editorial palette. Each token carries a light and a dark
/// value; the dark variant keeps the same warm, low-saturation character —
/// cream becomes a warm near-black, soft black becomes a warm off-white.
/// Colors resolve against the active appearance automatically, so call sites
/// stay appearance-agnostic.
enum EditorialColor {
    static let background = dynamic(light: 0xF7F3EC, dark: 0x17150F)
    static let surface = dynamic(light: 0xEFE8DC, dark: 0x201D16)
    static let primaryText = dynamic(light: 0x151412, dark: 0xF2ECE0)
    static let secondaryText = dynamic(light: 0x5F5A52, dark: 0xB0A99B)
    static let mutedText = dynamic(light: 0x958E82, dark: 0x7E7768)
    static let divider = dynamic(light: 0xE4DCCF, dark: 0x322E25)
    /// A strong, inverted accent (near-black on light, off-white on dark) used
    /// to tint prominent controls so they stay legible in either appearance.
    static let darkOverlay = dynamic(light: 0x151412, dark: 0xF2ECE0)
    static let mutedAccent = dynamic(light: 0x8A6F4D, dark: 0xB89368)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

enum EditorialFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        SurfaceFont.current.font(size: size, weight: weight)
    }

    static func ui(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        SurfaceFont.current.font(textStyle: style, weight: weight)
    }

    static func markdown(_ style: Font.TextStyle) -> Font {
        .system(style, design: .monospaced, weight: .regular)
    }
}

/// The user-selectable typeface applied to every surface (chrome) font in the app.
/// The note editor body stays monospaced; everything that goes through
/// `EditorialFont.display` / `EditorialFont.ui` follows this selection.
enum SurfaceFont: String, CaseIterable, Identifiable {
    case georgia
    case newYork
    case system
    case rounded
    case palatino
    case timesNewRoman
    case avenirNext
    case charter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .georgia: return "Georgia"
        case .newYork: return "New York"
        case .system: return "System"
        case .rounded: return "Rounded"
        case .palatino: return "Palatino"
        case .timesNewRoman: return "Times New Roman"
        case .avenirNext: return "Avenir Next"
        case .charter: return "Charter"
        }
    }

    func font(size: CGFloat, weight: Font.Weight) -> Font {
        if let family = customFamily {
            return Font.custom(family, fixedSize: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: systemDesign)
    }

    func font(textStyle: Font.TextStyle, weight: Font.Weight) -> Font {
        if let family = customFamily {
            return Font.custom(family, size: Self.pointSize(for: textStyle), relativeTo: textStyle)
                .weight(weight)
        }
        return .system(textStyle, design: systemDesign, weight: weight)
    }

    /// Installed font family for `Font.custom`, or `nil` to use a built-in system design.
    private var customFamily: String? {
        switch self {
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        case .timesNewRoman: return "Times New Roman"
        case .avenirNext: return "Avenir Next"
        case .charter: return "Charter"
        case .newYork, .system, .rounded: return nil
        }
    }

    private var systemDesign: Font.Design {
        switch self {
        case .newYork: return .serif
        case .rounded: return .rounded
        default: return .default
        }
    }

    /// Default point size per text style at the standard Dynamic Type size,
    /// used to scale custom fonts via `relativeTo:`.
    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    // MARK: - Persistence

    static let storageKey = "surfaceFontFamily"

    /// The currently selected surface font, defaulting to Georgia.
    static var current: SurfaceFont {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let font = SurfaceFont(rawValue: raw) else {
            return .georgia
        }
        return font
    }
}

/// The user-selectable color appearance for the whole app.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The `preferredColorScheme` value, or `nil` to follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static let storageKey = "appearanceMode"

    /// The currently selected appearance, defaulting to light.
    static var current: AppearanceMode {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let mode = AppearanceMode(rawValue: raw) else {
            return .light
        }
        return mode
    }
}

/// Observable store backing the font and appearance selections so the UI can
/// react to changes.
final class ThemeSettings: ObservableObject {
    @Published var fontFamily: SurfaceFont {
        didSet {
            UserDefaults.standard.set(fontFamily.rawValue, forKey: SurfaceFont.storageKey)
        }
    }

    @Published var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: AppearanceMode.storageKey)
        }
    }

    /// The home-screen greeting. User-editable and persisted; capped to two display lines by the
    /// editor that writes it. Falls back to ``defaultGreeting`` when cleared.
    @Published var greeting: String {
        didSet {
            UserDefaults.standard.set(greeting, forKey: Self.greetingStorageKey)
        }
    }

    static let greetingStorageKey = "home.greeting"
    static let defaultGreeting = "ob shell"

    init() {
        fontFamily = SurfaceFont.current
        appearance = AppearanceMode.current
        greeting = UserDefaults.standard.string(forKey: Self.greetingStorageKey) ?? Self.defaultGreeting
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    func editorialScreen() -> some View {
        background(EditorialColor.background.ignoresSafeArea())
            .tint(EditorialColor.primaryText)
            .toolbarBackground(EditorialColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(EditorialColor.divider)
            .frame(height: 0.5)
    }
}
