import SwiftUI

/// Brand tokens from docs/Brand.md for iOS surfaces.
/// Light: Signal Teal / Mist / Graphite. Dark: brighter teal on elevated charcoal, not a flat black slab.
enum MetraBrand {
    /// Signal Teal #0F766E
    static let signalTeal = Color(red: 0.059, green: 0.463, blue: 0.431)
    /// Dark-mode accent (brighter on charcoal) ~ #2DD4BF
    static let signalTealBright = Color(red: 0.176, green: 0.831, blue: 0.749)
    /// Mist #E6F4F1
    static let mist = Color(red: 0.902, green: 0.957, blue: 0.945)
    /// Graphite #1F2937
    static let graphite = Color(red: 0.122, green: 0.161, blue: 0.216)
    /// Dark elevated fill (teal-tinted charcoal, not #000)
    static let charcoalElevated = Color(red: 0.09, green: 0.13, blue: 0.14)
    /// Dark soft plate (pill / face plate)
    static let darkPill = Color(red: 0.149, green: 0.231, blue: 0.227)

    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? signalTealBright : signalTeal
    }

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark ? charcoalElevated : mist
    }

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkPill : Color.white.opacity(0.92)
    }

    static func pill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkPill : mist
    }

    static func openFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? graphite : Color.white
    }

    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? mist : graphite
    }

    static func userBubble(for scheme: ColorScheme) -> Color {
        accent(for: scheme).opacity(scheme == .dark ? 0.28 : 0.18)
    }

    static func assistantBubble(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkPill.opacity(0.9) : Color.white.opacity(0.85)
    }
}
