import SwiftUI

/// TEMPORARY dev gallery to verify the Warm Bloom Phase 0 components/typography render
/// correctly on the simulator (the CLI can't drive Xcode previews). Reached via the
/// `GALLERY=1` launch hook. Remove once Phase 1 has wired the components into real screens.
struct ComponentGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Group {
                    Text("Warm Bloom").font(Theme.Typography.title)
                    Text("a calmer way to eat").accentLine()
                }

                SectionEyebrow(text: "Rings")
                HStack(spacing: Theme.Spacing.lg) {
                    ConicRing(progress: 0.82, lineWidth: 16) {
                        VStack(spacing: 0) {
                            Text("1,840").font(Theme.Typography.numeral(24))
                            Text("kcal").font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.inkSecondary)
                        }
                    }.frame(width: 130, height: 130)
                    ConicRing(progress: 0.6, lineWidth: 8, fill: Theme.Palette.sage) {
                        Text("60%").font(Theme.Typography.numeral(14))
                    }.frame(width: 66, height: 66)
                    ConicRing(progress: 0.35, lineWidth: 8, fill: Theme.Palette.bandOver) {
                        Text("35%").font(Theme.Typography.numeral(14))
                    }.frame(width: 66, height: 66)
                }

                SectionEyebrow(text: "Micro bloom")
                MicroBloom(petals: MicroBloom.petals(
                    values:     [101, 13, 1.0, 83, 512, 8.4, 6.6, 284],
                    references: [100, 21, 2.0, 100, 900, 11, 7.5, 370]))
                    .frame(width: 200, height: 200)
                    .frame(maxWidth: .infinity)

                Divider()
                SectionEyebrow(text: "Buttons")
                Button("Read this meal") {}.buttonStyle(.primary)
                Button("Enter it manually") {}.buttonStyle(.secondary)
                HStack {
                    Button("Restore") {}.buttonStyle(.ghost(muted: true))
                    Spacer()
                    Button("Terms") {}.buttonStyle(.ghost)
                }

                SectionEyebrow(text: "Chips")
                HStack {
                    Chip(text: "Full plate", systemImage: "checkmark", variant: .sageTint)
                    Chip(text: "Best value", variant: .amberTint)
                    Chip(text: "Camera", systemImage: "camera", variant: .dark)
                }
                HStack {
                    Chip(text: "Breakfast", variant: .outline, selected: true)
                    Chip(text: "Lunch", variant: .outline)
                    Chip(text: "Dinner", variant: .outline)
                }

                SectionEyebrow(text: "Cards")
                WarmCard {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionEyebrow(text: "Nutrient sufficiency")
                        Text("A calm, even rhythm this week.").accentLine()
                    }
                }
                WarmCard(honey: true) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("1,840").font(Theme.Typography.numeral(40))
                        Text("of 2,100 kcal").font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                    }
                }

                typeSpecimen
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Palette.background)
    }

    private var typeSpecimen: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title 28 ExtraBold").font(Theme.Typography.title)
            Text("Headline 22 Bold").font(Theme.Typography.headline)
            Text("Body large 19").font(Theme.Typography.bodyLarge)
            Text("Body 16 regular — the quick brown fox").font(Theme.Typography.body)
            Text("Label 14 semibold").font(Theme.Typography.label)
            Text("Caption 13 medium").font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
            Text("1,234,567,890").font(Theme.Typography.numeral(22))
        }
        .foregroundStyle(Theme.Palette.ink)
    }
}

#Preview { ComponentGallery() }
