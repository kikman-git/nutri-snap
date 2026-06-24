import SwiftUI
import Charts

/// Trends tab — calm, nutrition-only insights over logged history (PRD §2 gentle tone).
/// Charts/numbers are computed on-device (`TrendsAnalysis`); the "reflect on my week" button is
/// the only AI call, opt-in, one per tap. Nutrient sufficiency is judged on the rolling average,
/// never daily pass/fail (see memory: nutrition-app-direction).
struct TrendsScreen: View {
    @Environment(MealStore.self) private var store
    private let reflector: WeeklyReflecting

    @State private var window: TrendsAnalysis.Window = .week
    @State private var showReflection = false
    @State private var showProfile = false

    init(reflector: WeeklyReflecting = GeminiReflector.shared) {
        self.reflector = reflector
    }

    private var target: Nutrients { store.target }

    private var analysis: TrendsAnalysis {
        TrendsAnalysis.compute(days: store.rollups, target: target,
                               references: store.references, window: window)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header

                if analysis.hasEnoughData {
                    summaryCard
                    nutrientCard
                    trendCard
                    averagesRow
                    rhythmCard
                    if !analysis.patterns.isEmpty { patternsCard }
                    reflectButton
                } else {
                    earlyState
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Palette.background)
        .sheet(isPresented: $showReflection) {
            ReflectionSheet(input: reflectionInput, reflector: reflector)
        }
        .sheet(isPresented: $showProfile) { ProfileSettingsSheet() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Trends")
                    .font(Theme.Typography.screenTitle)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Button { showProfile = true } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                .accessibilityLabel("Your details")
            }

            Picker("Window", selection: $window) {
                ForEach(TrendsAnalysis.Window.allCases) { w in
                    Text(w.label).tag(w)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var summaryCard: some View {
        Text(analysis.summary)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.accent.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// The headline of the app's evolved direction: rolling nutrient adequacy, gently shown.
    private var nutrientCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Nutrient sufficiency")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Palette.ink)
                Text("Average over the last \(window.label), vs daily reference")
                    .font(.system(.caption2))
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            ForEach(Nutrient.allCases) { nutrient in
                nutrientRow(nutrient)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func nutrientRow(_ n: Nutrient) -> some View {
        let avg = analysis.nutrientAverages[n] ?? 0
        let ref = store.references[n]
        let ratio = analysis.adequacy(n)
        let state = analysis.sufficiency(n)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(n.displayName)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("\(fmt(avg)) / \(fmt(ref)) \(n.unit)")
                    .font(.system(.caption2))
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            ProgressView(value: min(ratio, 1.0))
                .tint(Theme.Palette.accent)
            Text(state.label)
                .font(.system(.caption2))
                .foregroundStyle(state == .low ? Theme.Palette.accent : Theme.Palette.inkSecondary)
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Daily calories")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)

            Chart {
                ForEach(analysis.points) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("kcal", point.kcal)
                    )
                    .foregroundStyle(point.band.fill)
                    .cornerRadius(4)
                }
                RuleMark(y: .value("Target", analysis.target.kcal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.Palette.inkSecondary.opacity(0.5))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("target \(Int(analysis.target.kcal))")
                            .font(.system(.caption2))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                    }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: window == .week ? 1 : 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartLegend(.hidden)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var averagesRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            StatTile(label: "Avg / day", value: "\(Int(analysis.averageKcal)) kcal")
            StatTile(label: "On track", value: "\(analysis.inRangeCount)/\(analysis.loggedDayCount)")
            StatTile(label: "Avg protein", value: "\(Int(analysis.averageMacros.protein)) g")
        }
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("\(analysis.inRangeCount) of \(analysis.loggedDayCount) days on track")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.ink)
            HStack(spacing: 3) {
                ForEach(analysis.points) { point in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(point.band.fill)
                        .frame(height: 18)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var patternsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(analysis.patterns, id: \.self) { pattern in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.Palette.accent)
                    Text(pattern)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.ink)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var reflectButton: some View {
        Button { showReflection = true } label: {
            Label("Reflect on my \(analysis.window.period)", systemImage: "sparkles")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.surface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Palette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var earlyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.accent.opacity(0.6))
            Text("Your trends are warming up")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.ink)
            Text(earlyStateMessage)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xxl)
    }

    /// Honest about the gate: trends need a few logged *days* (not meals — logging five meals in one
    /// day still counts as one). Show progress so it doesn't read as a dead end.
    private var earlyStateMessage: String {
        let have = analysis.loggedDayCount
        guard have > 0 else {
            return "Snap meals across about four days and your patterns will appear here. No rush."
        }
        let left = max(TrendsAnalysis.minDaysForTrends - have, 1)
        return "\(have) day\(have == 1 ? "" : "s") logged so far — about \(left) more and your trends appear here."
    }

    private func fmt(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", v) : String(Int(v.rounded()))
    }

    private var reflectionInput: ReflectionInput {
        let a = analysis
        let low = Nutrient.allCases.filter { a.sufficiency($0) == .low }.map(\.displayName)
        return ReflectionInput(
            windowLabel: a.window.label,
            loggedDays: a.loggedDayCount,
            avgKcal: a.averageKcal,
            target: target,
            avgProtein: a.averageMacros.protein,
            avgCarbs: a.averageMacros.carbs,
            avgFat: a.averageMacros.fat,
            inRange: a.inRangeCount,
            under: a.underCount,
            over: a.overCount,
            lowNutrients: low)
    }
}

/// Small numeric tile for the averages row.
private struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.ink)
            Text(label)
                .font(.system(.caption2))
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

/// The opt-in AI reflection, in a calm half-sheet. Loading / result / gentle failure.
private struct ReflectionSheet: View {
    let input: ReflectionInput
    let reflector: WeeklyReflecting

    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let text {
                        Text(text)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.ink)
                    } else if failed {
                        Text("Couldn't pull that together just now. Mind trying again in a bit?")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                    } else {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView().tint(Theme.Palette.accent)
                            Text("Looking back over your \(input.windowLabel)…")
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.inkSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Palette.background)
            .navigationTitle("Your \(input.windowLabel.contains("7") ? "week" : "month")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
            .task {
                do { text = try await reflector.reflect(input) }
                catch { failed = true }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    TrendsScreen(reflector: MockReflector()).environment(MealStore.sample)
}
