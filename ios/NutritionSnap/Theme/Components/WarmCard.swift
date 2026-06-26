import SwiftUI

/// Surface card — cream fill, radius 24, soft warm-brown shadow. The default container
/// for most Warm Bloom content. Pass `gradient` for the honey summary/streak variant.
struct WarmCard<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.lg
    var honey = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                if honey {
                    shape.fill(Theme.Gradient.honey)
                } else {
                    shape.fill(Theme.Palette.surface)
                }
            }
            .warmCardShadow()
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        WarmCard {
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow(text: "Nutrient sufficiency")
                Text("A calm, even rhythm this week.").accentLine()
            }
        }
        WarmCard(honey: true) {
            VStack(alignment: .leading, spacing: 6) {
                Text("1,840").font(Theme.Typography.numeral(40))
                Text("of 2,100 kcal · in range").font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Palette.background)
}
