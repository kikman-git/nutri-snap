import SwiftUI

/// Design tokens — the **"Warm Bloom"** system (see `docs/WARM_BLOOM_REVAMP.md`).
/// Anthropic-inspired warm-minimal, but our own brand: cream canvas, one warm clay
/// accent + a sage second accent, an amber gradient for primary CTAs, Newsreader-italic
/// clay accent lines, soft warm-brown shadows. Colors live in `Assets.xcassets`; this is
/// the typed access layer. Never hardcode hex/sizes at call sites — add a token here.
enum Theme {
    enum Palette {
        // Canvas + ink
        static let background   = Color("Background")
        static let surface      = Color("Surface")
        static let ink          = Color("Ink")
        static let inkSecondary = Color("InkSecondary")
        // Accents
        static let accent       = Color("Accent")        // the one warm clay accent
        static let sage         = Color("Sage")          // second accent — steady / positive
        // Fills
        static let honey        = Color("Honey")
        static let hairline     = Color("Hairline")
        /// Resting tab-bar icon — a muted sage-taupe (#B8AC99), lighter than `inkSecondary`.
        /// Code-defined (single use); promote to a colorset if it spreads.
        static let tabInactive  = Color(red: 184/255, green: 172/255, blue: 153/255)
        static let sageTintBg   = Color("SageTintBg")    // pale sage chip / under-cell fill
        static let sageText     = Color("SageText")      // text on sage-tint
        static let amberTintBg  = Color("AmberTintBg")   // secondary-button fill
        // Gradient stops (used via Theme.Gradient)
        static let gradTop      = Color("GradTop")
        static let gradBottom   = Color("GradBottom")
        // Calendar bands (over is warm amber — never red, PRD §5.3)
        static let bandUnder    = Color("BandUnder")     // pale sage-tint
        static let bandIn       = Color("BandIn")        // == accent: aesthetic & "on-track" are one decision
        static let bandOver     = Color("BandOver")      // soft amber
        static let bandEmpty    = Color("BandEmpty")     // ring / progress track
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
        static let chip:    CGFloat = 10   // legacy small chips
        static let control: CGFloat = 14   // legacy controls
        static let tile:    CGFloat = 14
        static let input:   CGFloat = 18
        static let card:    CGFloat = 24
        // Pills use `Capsule()` (radius 999), not a number.
    }

    /// Primary-CTA amber gradient — `linear(≈150°, #F2B880 → #E8A87C)`.
    enum Gradient {
        static let primary = LinearGradient(
            colors: [Palette.gradTop, Palette.gradBottom],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        /// Soft honey wash used on summary / streak cards.
        static let honey = LinearGradient(
            colors: [Palette.honey.opacity(0.55), Palette.amberTintBg],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Soft warm-brown shadows. CSS specs carry a negative spread we can't express in
    /// SwiftUI, so these are tuned approximations (lighter opacity, tighter offset).
    enum Shadow {
        /// Warm-brown tint shared by card shadows (≈ rgba(120,90,50,·)).
        static let warm = Color(red: 120/255, green: 90/255, blue: 50/255)
    }

    /// Hanken Grotesk (UI + numbers) + Newsreader italic (clay accent line). 11-step
    /// scale (plan §0.2). Static weights are vendored, so the PostScript name carries the
    /// weight — never apply `.weight()` on top. `relativeTo:` keeps Dynamic Type scaling.
    enum Typography {
        private static func hanken(_ ps: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
            .custom(ps, size: size, relativeTo: style)
        }

        static let displayXL = hanken("HankenGrotesk-ExtraBold", 56, .largeTitle) // splash wordmark
        static let display   = hanken("HankenGrotesk-ExtraBold", 38, .largeTitle) // reflect headline
        static let title     = hanken("HankenGrotesk-ExtraBold", 28, .title)      // screen titles, meal name
        static let headline  = hanken("HankenGrotesk-Bold",      22, .title2)     // section heads
        static let bodyLarge = hanken("HankenGrotesk-Regular",   19, .body)       // lead paragraphs
        static let body      = hanken("HankenGrotesk-Regular",   16, .body)       // default
        static let label     = hanken("HankenGrotesk-SemiBold",  14, .subheadline)// buttons, field labels
        static let caption   = hanken("HankenGrotesk-Medium",    13, .footnote)   // timestamps, meta
        static let overline  = hanken("HankenGrotesk-Bold",      13, .caption)    // section eyebrows (uppercase + tracking at use site)
        static let accent    = Font.custom("Newsreader-Italic", size: 17, relativeTo: .body) // the clay feeling line

        /// Tabular extra-bold numerals — for every number on a surface.
        static func numeral(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
            .custom("HankenGrotesk-ExtraBold", size: size, relativeTo: style).monospacedDigit()
        }

        // Back-compat aliases for screens not yet migrated to the new tokens (Phase 1).
        static let screenTitle  = title
        static let sectionTitle = headline
    }
}

// MARK: - Text helpers (brand signatures)

extension Text {
    /// Newsreader-italic clay one-liner — the Warm Bloom brand signature.
    func accentLine() -> Text {
        self.font(Theme.Typography.accent).foregroundStyle(Theme.Palette.accent)
    }

    /// Uppercase tracked eyebrow over cards/sections.
    func overline() -> some View {
        self.font(Theme.Typography.overline)
            .tracking(2)
            .foregroundStyle(Theme.Palette.inkSecondary)
            .textCase(.uppercase)
    }
}

// MARK: - Shadow helpers

extension View {
    /// Soft warm-brown card shadow.
    func warmCardShadow() -> some View {
        shadow(color: Theme.Shadow.warm.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    /// Amber glow under primary (gradient) buttons.
    func amberButtonShadow() -> some View {
        shadow(color: Theme.Palette.gradBottom.opacity(0.5), radius: 12, x: 0, y: 8)
    }

    /// A lighter lift for floating elements (FAB, sheets).
    func liftedShadow() -> some View {
        shadow(color: Theme.Shadow.warm.opacity(0.22), radius: 16, x: 0, y: 8)
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
        case .inRange: return Theme.Palette.surface     // light text on clay
        case .under:   return Theme.Palette.sageText     // sage on pale sage-tint
        case .over:    return Theme.Palette.ink          // ink on soft amber
        case .none:    return Theme.Palette.inkSecondary
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

extension EnergyShape {
    /// Semantic tint for the energy ribbon / dot — sage (calm) → amber → clay. Never red:
    /// "quick rise" is the warmest, but caution lives in clay, not alarm (PRD constraint).
    var tint: Color {
        switch self {
        case .steady:     return Theme.Palette.sage
        case .gentleRise: return Theme.Palette.bandOver   // soft amber
        case .spike:      return Theme.Palette.accent     // clay
        }
    }

    /// Text color for the label beside the ribbon (slightly deeper than the line tint).
    var labelColor: Color {
        switch self {
        case .steady:     return Theme.Palette.sageText
        case .gentleRise: return Theme.Palette.accent
        case .spike:      return Theme.Palette.accent
        }
    }
}
