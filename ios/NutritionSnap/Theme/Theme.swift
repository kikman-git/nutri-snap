import SwiftUI

/// Design tokens (PRD §7) — Anthropic-inspired warm-minimal, but our own brand.
/// Colors live in `Assets.xcassets`; this is the typed access layer. The hex values
/// are placeholders until real brand colors are chosen.
enum Theme {
    enum Palette {
        static let background   = Color("Background")
        static let surface      = Color("Surface")
        static let ink          = Color("Ink")
        static let inkSecondary = Color("InkSecondary")
        static let accent       = Color("Accent")     // the one warm clay/coral accent
        static let bandUnder    = Color("BandUnder")
        static let bandIn       = Color("BandIn")      // == accent: aesthetic & "on-track" are one decision
        static let bandOver     = Color("BandOver")
        static let bandEmpty    = Color("BandEmpty")
    }

    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let chip:    CGFloat = 10
        static let control: CGFloat = 14
        static let card:    CGFloat = 20
    }

    /// System font for now. Swap to a humanist face here later (PRD §7) — one place.
    enum Typography {
        static let screenTitle  = Font.system(.largeTitle).weight(.semibold)
        static let sectionTitle = Font.system(.title3).weight(.semibold)
        static let body         = Font.system(.body)
        static let caption      = Font.system(.subheadline)
    }
}

extension DayBand {
    /// Calendar fill color. "Over" is warm amber — never red (PRD §5.3).
    var fill: Color {
        switch self {
        case .under:   return Theme.Palette.bandUnder
        case .inRange: return Theme.Palette.bandIn
        case .over:    return Theme.Palette.bandOver
        case .none:    return Theme.Palette.bandEmpty
        }
    }

    /// Readable number/text on top of `fill`.
    var onFill: Color {
        switch self {
        case .inRange: return Theme.Palette.surface      // light text on clay
        case .none:    return Theme.Palette.inkSecondary
        default:       return Theme.Palette.ink
        }
    }

    /// Gentle, non-judgmental wording (PRD §5.3).
    var gentleLabel: String {
        switch self {
        case .under:   return "A lighter day"
        case .inRange: return "On track"
        case .over:    return "A fuller day"
        case .none:    return "No log yet"
        }
    }

    /// Compact form for the calendar legend.
    var shortLabel: String {
        switch self {
        case .under:   return "Lighter"
        case .inRange: return "On track"
        case .over:    return "Fuller"
        case .none:    return "—"
        }
    }
}
