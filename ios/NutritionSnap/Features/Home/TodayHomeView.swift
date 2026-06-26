import SwiftUI

/// Today · Home (Warm Bloom screen 2) — the Snap-tab idle surface (D4 home-first). A calm landing:
/// greeting, today's kcal ring + macro line, today's meals, and a gentle gap teaser into Fill the
/// Gaps. The center FAB (in `RootView`) launches the camera; this screen never shows the viewfinder.
struct TodayHomeView: View {
    @Environment(MealStore.self) private var store
    var onOpenGaps: () -> Void

    @State private var todayEntries: [Entry] = []
    @State private var showProfile = false

    private var target: Nutrients { store.target }
    private var references: NutrientAmounts { store.references }
    private var rollup: DayRollup? { store.rollups.first { $0.id == DayLog.key(for: Date()) } }
    private var totals: Nutrients { rollup?.totals ?? .zero }
    private var micros: NutrientAmounts { rollup?.microTotals ?? .zero }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            todayCard
            if !todayEntries.isEmpty { meals }
            if let gap = lowestGap { gapTeaser(gap) }
            Spacer(minLength: 0)
        }
        .task(id: store.recentEntry?.id) { todayEntries = await store.entries(on: Date()).entries }
        .sheet(isPresented: $showProfile) { ProfileSettingsSheet() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateLine).overline()
                Text(greeting).font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
            }
            Spacer()
            Button { showProfile = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.Palette.inkSecondary)
                    .frame(width: 40, height: 40)
                    .background(Theme.Palette.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
            }
            .accessibilityLabel("Your details")
        }
    }

    private var todayCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            ConicRing(progress: progress, lineWidth: 11, fill: Theme.Palette.bandOver) {
                VStack(spacing: 0) {
                    Text("\(Int(totals.kcal.rounded()))").font(Theme.Typography.numeral(22)).foregroundStyle(Theme.Palette.ink)
                    Text("of \(Int(target.kcal.rounded()))").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(todayLine).font(Theme.Typography.accent).foregroundStyle(Theme.Palette.sageText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.md) {
                    macro("C", totals.carbs); macro("P", totals.protein); macro("F", totals.fat)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .background(
            LinearGradient(colors: [Theme.Palette.surface, Theme.Palette.amberTintBg],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .warmCardShadow()
    }

    private func macro(_ label: String, _ grams: Double) -> some View {
        HStack(spacing: 4) {
            Text(label).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
            Text("\(Int(grams.rounded()))g").font(Theme.Typography.numeral(13)).foregroundStyle(Theme.Palette.ink)
        }
    }

    private var meals: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(text: "Today's meals")
            ForEach(todayEntries.sorted { $0.capturedAt < $1.capturedAt }) { mealRow($0) }
        }
    }

    private func mealRow(_ e: Entry) -> some View {
        HStack(spacing: 13) {
            MealPhoto(path: e.photoPath, symbol: e.photoSymbol ?? "fork.knife")
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(mealName(e)).font(Theme.Typography.label).foregroundStyle(Theme.Palette.ink).lineLimit(1)
                    Spacer()
                    Text(timeString(e.capturedAt)).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.tabInactive)
                }
                HStack(spacing: 6) {
                    if let energy = e.energy { Circle().fill(energy.tint).frame(width: 8, height: 8) }
                    Text("\(Int(e.totals.kcal.rounded())) kcal\(e.energy.map { " · \($0.label.lowercased())" } ?? "")")
                        .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
        }
        .padding(11)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
    }

    private func gapTeaser(_ n: Nutrient) -> some View {
        Button(action: onOpenGaps) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "leaf.fill").foregroundStyle(Theme.Palette.sageText)
                    .frame(width: 40, height: 40).background(Theme.Palette.surface, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("A little low on \(n.displayName.lowercased()) today")
                        .font(Theme.Typography.label).foregroundStyle(Theme.Palette.ink)
                    Text("2 easy ideas to round it out ›").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.sageText)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.sageTintBg, in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var progress: Double { target.kcal > 0 ? totals.kcal / target.kcal : 0 }

    private var lowestGap: Nutrient? {
        var best: (Nutrient, Double)?
        for n in Nutrient.allCases where n != .protein {
            let ref = references[n]
            guard ref > 0 else { continue }
            let a = micros[n] / ref
            if a < 0.85, best == nil || a < best!.1 { best = (n, a) }
        }
        return best?.0
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<12:   return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var todayLine: String {
        guard totals.kcal > 0 else { return "a fresh start to the day" }
        switch progress {
        case ..<0.45:  return "a gentle start to the day"
        case ..<0.85:  return "a steady day so far"
        case ...1.10:  return "a full, balanced day"
        default:       return "a fuller day — and that's okay"
        }
    }

    private var dateLine: String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return f.string(from: Date())
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("Hmm"); return f.string(from: date)
    }

    private func mealName(_ e: Entry) -> String {
        e.items.map(\.name).first { !$0.isEmpty } ?? e.mealSlot?.label ?? "Your meal"
    }
}

#Preview {
    ScrollView { TodayHomeView(onOpenGaps: {}).padding(Theme.Spacing.lg) }
        .background(Theme.Palette.background)
        .environment(MealStore.sample)
}
