import SwiftUI

/// Educational "how much do I need" reference, embedded in Journal (PRD §5.3). Lets you target
/// food or supplements. A ✓ marks the nutrients the app estimates from your photos; the rest are
/// reference-only (log via supplements / bloodwork).
struct NutrientGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily nutrient needs")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Palette.ink)
                Text("General adult guidance, per day. ✓ = the app estimates it from your photos.")
                    .font(.system(.caption2))
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }

            ForEach(NutrientGuideEntry.Category.allCases) { category in
                categorySection(category)
            }

            Text("Reference: Japanese MHLW dietary intakes (adult). Not medical advice.")
                .font(.system(.caption2))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .padding(.top, Theme.Spacing.xs)
        }
    }

    private func categorySection(_ category: NutrientGuideEntry.Category) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(category.rawValue)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)

            VStack(spacing: 0) {
                let entries = NutrientGuide.entries(in: category)
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry)
                    if index < entries.count - 1 {
                        Divider().overlay(Theme.Palette.ink.opacity(0.06))
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private func row(_ entry: NutrientGuideEntry) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(entry.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.ink)
                    if entry.tracked {
                        Text("✓")
                            .font(.system(.caption2, weight: .bold))
                            .foregroundStyle(Theme.Palette.accent)
                    }
                }
                Text("\(entry.benefit) · \(entry.sources)")
                    .font(.system(.caption2))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(entry.dailyAmount)
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .monospacedDigit()
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
}

#Preview {
    ScrollView {
        NutrientGuideView().padding()
    }
    .background(Theme.Palette.background)
}
