import SwiftUI

/// Primary CTA — amber gradient pill, white label, soft amber glow. Full-width by
/// default (the design's primary buttons span the content width). Compose the label in
/// the `Button` (text, or a `Label`/`HStack` for an icon).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.label)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Theme.Gradient.primary, in: Capsule())
            .amberButtonShadow()
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary — amber-tint fill, clay label, hairline border. Full-width pill.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.Palette.amberTintBg, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Tertiary — plain clay text, no fill (Restore, Terms, quiet inline actions).
struct GhostButtonStyle: ButtonStyle {
    var muted = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.label)
            .foregroundStyle(muted ? Theme.Palette.inkSecondary : Theme.Palette.accent)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// Amber-gradient primary CTA.
    static var primary: PrimaryButtonStyle { .init() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    /// Amber-tint outline secondary.
    static var secondary: SecondaryButtonStyle { .init() }
}
extension ButtonStyle where Self == GhostButtonStyle {
    /// Plain clay text. `.ghost(muted: true)` for a quiet grey.
    static var ghost: GhostButtonStyle { .init() }
    static func ghost(muted: Bool) -> GhostButtonStyle { .init(muted: muted) }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        Button("Read this meal") {}.buttonStyle(.primary)
        Button {} label: { Label("Reflect on my week", systemImage: "sparkles") }
            .buttonStyle(.primary)
        Button("Enter it manually") {}.buttonStyle(.secondary)
        HStack {
            Button("Restore") {}.buttonStyle(.ghost(muted: true))
            Button("Terms") {}.buttonStyle(.ghost)
        }
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Palette.background)
}
