import SwiftUI

/// Small pill label/tag. Used for badges, meal-slot selection, glass capture chips.
struct Chip: View {
    enum Variant { case sageTint, amberTint, neutral, dark, outline }

    let text: String
    var systemImage: String? = nil
    var variant: Variant = .neutral
    var selected = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(Theme.Typography.label)
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(background, in: Capsule())
        .overlay {
            if variant == .outline {
                Capsule().strokeBorder(selected ? Theme.Palette.accent : Theme.Palette.hairline,
                                       lineWidth: selected ? 1.5 : 1)
            }
        }
    }

    private var foreground: Color {
        switch variant {
        case .sageTint:  return Theme.Palette.sageText
        case .amberTint: return Theme.Palette.accent
        case .neutral:   return Theme.Palette.inkSecondary
        case .dark:      return .white
        case .outline:   return selected ? Theme.Palette.accent : Theme.Palette.inkSecondary
        }
    }

    private var background: Color {
        switch variant {
        case .sageTint:  return Theme.Palette.sageTintBg
        case .amberTint: return Theme.Palette.amberTintBg
        case .neutral:   return Theme.Palette.hairline
        case .dark:      return Theme.Palette.ink
        case .outline:   return selected ? Theme.Palette.amberTintBg : .clear
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        HStack {
            Chip(text: "Looks like a full plate", systemImage: "checkmark", variant: .sageTint)
            Chip(text: "Best value", variant: .amberTint)
        }
        HStack {
            Chip(text: "Breakfast", variant: .outline, selected: true)
            Chip(text: "Lunch", variant: .outline)
            Chip(text: "Dinner", variant: .outline)
        }
        HStack {
            Chip(text: "Camera", systemImage: "camera", variant: .dark)
            Chip(text: "Library", systemImage: "photo", variant: .neutral)
        }
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Palette.background)
}
