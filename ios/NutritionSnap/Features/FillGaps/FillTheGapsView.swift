import SwiftUI

/// Fill the Gaps (Warm Bloom screen 7) — gentle, everyday foods that top up the day's shortfalls.
/// Plus-gated by the caller (Today teaser / Logged nudge route here only when subscribed). Reads
/// today's rollup vs `store.references`; the reminder CTA is deferred (D9 — needs notifications, v2+).
struct FillTheGapsView: View {
    @Environment(MealStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct Gap: Identifiable {
        let nutrient: Nutrient
        let adequacy: Double
        var id: String { nutrient.rawValue }
    }

    private var references: NutrientAmounts { store.references }
    private var todayMicros: NutrientAmounts {
        store.rollups.first { $0.id == DayLog.key(for: Date()) }?.microTotals ?? .zero
    }

    private var gaps: [Gap] {
        var result: [Gap] = []
        for n in Nutrient.allCases where n != .protein {
            let ref = references[n]
            guard ref > 0 else { continue }
            let a = todayMicros[n] / ref
            if a < 0.85 { result.append(Gap(nutrient: n, adequacy: a)) }
        }
        result.sort { $0.adequacy < $1.adequacy }
        return Array(result.prefix(4))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                if gaps.isEmpty { balanced } else { cards }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Palette.inkSecondary)
                        .frame(width: 38, height: 38)
                        .background(Theme.Palette.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 1) {
                    SectionEyebrow(text: "Fill the gaps")
                    Text("A little more today").font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
                }
            }
            Text("You're a bit short on a few things. Here are simple, everyday foods that top them up — rough ideas, not exact numbers.")
                .font(Theme.Typography.body).foregroundStyle(Theme.Palette.inkSecondary)
        }
    }

    private var cards: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(gaps) { gapCard($0) }
            if let first = gaps.first?.nutrient, let tip = NutrientFoods.tip(for: first) { tipCard(tip) }
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func gapCard(_ gap: Gap) -> some View {
        WarmCard(padding: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(NutrientFoods.code(gap.nutrient))
                        .font(.custom("HankenGrotesk-ExtraBold", size: 13)).foregroundStyle(Theme.Palette.sageText)
                        .frame(width: 40, height: 40).background(Theme.Palette.sageTintBg, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(gap.nutrient.displayName).font(Theme.Typography.headline).foregroundStyle(Theme.Palette.ink)
                        Text("at \(pct(gap.adequacy))% today · aim a little higher")
                            .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(badge(gap)).font(Theme.Typography.numeral(14)).foregroundStyle(Theme.Palette.accent)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(NutrientFoods.suggestions(for: gap.nutrient)) { foodTile($0) }
                }
            }
        }
    }

    private func foodTile(_ food: FoodSuggestion) -> some View {
        VStack(spacing: 3) {
            Text(food.emoji).font(.system(size: 26))
            Text(food.name).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(food.boost).font(.custom("HankenGrotesk-Bold", size: 11)).foregroundStyle(Theme.Palette.sageText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10).padding(.horizontal, 6)
        .background(Theme.Palette.background, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    }

    private func tipCard(_ tip: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("🌙").font(.system(size: 20))
            Text(tip).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.sageText)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.sageTintBg, in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
    }

    private var balanced: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 44, weight: .light)).foregroundStyle(Theme.Palette.sageText)
                .frame(width: 120, height: 120).background(Theme.Palette.sageTintBg, in: Circle())
            Text("Beautifully balanced today").font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
            Text("nothing to round out — lovely").accentLine()
        }
        .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, Theme.Spacing.xxl)
    }

    private func pct(_ a: Double) -> Int { Int((max(a, 0) * 100).rounded()) }

    private func badge(_ gap: Gap) -> String {
        let gapAmount = max(references[gap.nutrient] - todayMicros[gap.nutrient], 0)
        switch gap.nutrient {
        case .fiber, .omega3: return "+\(Int(gapAmount.rounded()))\(gap.nutrient.unit)"
        default:              return "+\(Int(((1 - gap.adequacy) * 100).rounded()))%"
        }
    }
}

#Preview {
    FillTheGapsView().environment(MealStore.sample)
}
