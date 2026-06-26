import SwiftUI
import Charts

struct TrendsScreen: View {
    @Environment(MealStore.self) private var store
    private let reflector: WeeklyReflecting

    @State private var window: TrendsAnalysis.Window = .week
    @State private var showReflection = false
    @State private var showProfile = false

    init(reflector: WeeklyReflecting = GeminiReflector.shared) {
        self.reflector = reflector
        _showReflection = State(initialValue: ProcessInfo.processInfo.environment["OPEN_REFLECT"] != nil)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionEyebrow(text: "Trends")
                    Text("Last \(window.label)").font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
                }
                Spacer()
                Button { showProfile = true } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .frame(width: 40, height: 40)
                        .background(Theme.Palette.surface, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                }
                .accessibilityLabel("Your details")
            }
            Picker("Window", selection: $window) {
                ForEach(TrendsAnalysis.Window.allCases) { w in Text(w.label).tag(w) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var summaryCard: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(analysis.summary).font(Theme.Typography.body).foregroundStyle(Theme.Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.amberTintBg, in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
    }

    private var nutrientCard: some View {
        WarmCard(padding: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionEyebrow(text: "Nutrient sufficiency · focused 12")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 4),
                          spacing: Theme.Spacing.md) {
                    ForEach(Nutrient.allCases) { sufficiencyDial($0) }
                }
            }
        }
    }

    private func sufficiencyDial(_ n: Nutrient) -> some View {
        let ratio = analysis.adequacy(n)
        let color = analysis.sufficiency(n) == .low ? Theme.Palette.bandOver : Theme.Palette.sage
        return VStack(spacing: 5) {
            ConicRing(progress: ratio, lineWidth: 5, fill: color) {
                Text("\(Int((min(ratio, 1) * 100).rounded()))")
                    .font(Theme.Typography.numeral(12)).foregroundStyle(Theme.Palette.ink)
            }
            .frame(width: 46, height: 46)
            Text(ShareCard.shortName(n))
                .font(.custom("HankenGrotesk-SemiBold", size: 10))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .lineLimit(1)
        }
    }

    private var trendCard: some View {
        WarmCard(padding: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    SectionEyebrow(text: "Daily calories")
                    Spacer()
                    Text("vs \(Int(target.kcal))").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
                }
                Chart {
                    RuleMark(y: .value("Target", target.kcal))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(Theme.Palette.inkSecondary.opacity(0.4))
                    ForEach(analysis.points) { p in
                        AreaMark(x: .value("Day", p.date, unit: .day), y: .value("kcal", p.kcal))
                            .foregroundStyle(LinearGradient(
                                colors: [Theme.Palette.bandOver.opacity(0.28), Theme.Palette.bandOver.opacity(0)],
                                startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Day", p.date, unit: .day), y: .value("kcal", p.kcal))
                            .foregroundStyle(Theme.Palette.bandOver)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        if p.date == bestDate {
                            PointMark(x: .value("Day", p.date, unit: .day), y: .value("kcal", p.kcal))
                                .foregroundStyle(Theme.Palette.accent).symbolSize(60)
                        }
                    }
                }
                .frame(height: 96)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }
        }
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("\(analysis.inRangeCount) of \(analysis.loggedDayCount) days on track")
                    .font(Theme.Typography.label).foregroundStyle(Theme.Palette.sageText)
                Spacer()
                Text("a good rhythm").font(Theme.Typography.accent).foregroundStyle(Theme.Palette.sage)
            }
            HStack(spacing: 4) {
                ForEach(analysis.points) { p in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(p.band == .inRange ? Theme.Palette.sage : Theme.Palette.sage.opacity(0.4))
                        .frame(height: 18).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.sageTintBg, in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
    }

    private var patternsCard: some View {
        WarmCard(padding: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(analysis.patterns, id: \.self) { pattern in
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.Palette.accent)
                        Text(pattern).font(Theme.Typography.body).foregroundStyle(Theme.Palette.ink)
                    }
                }
            }
        }
    }

    private var reflectButton: some View {
        Button { showReflection = true } label: {
            Label("Reflect on my \(analysis.window.period)", systemImage: "leaf.fill")
        }
        .buttonStyle(.primary)
    }

    private var earlyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "leaf")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 140, height: 140)
                .background(Theme.Palette.amberTintBg, in: Circle())
            Text("Your trends are warming up").font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
            Text(earlyStateMessage).accentLine().multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, Theme.Spacing.xxl)
    }

    private var earlyStateMessage: String {
        let have = analysis.loggedDayCount
        guard have > 0 else {
            return "snap meals across about four days and your patterns appear here"
        }
        let left = max(TrendsAnalysis.minDaysForTrends - have, 1)
        return "\(have) day\(have == 1 ? "" : "s") logged — about \(left) more and your trends appear"
    }

    private var bestDate: Date? {
        analysis.points.min { abs($0.kcal - target.kcal) < abs($1.kcal - target.kcal) }?.date
    }

    private var reflectionInput: ReflectionInput {
        let a = analysis
        let low = Nutrient.allCases.filter { a.sufficiency($0) == .low }.map(\.displayName)
        return ReflectionInput(
            windowLabel: a.window.label, loggedDays: a.loggedDayCount,
            avgKcal: a.averageKcal, target: target,
            avgProtein: a.averageMacros.protein, avgCarbs: a.averageMacros.carbs, avgFat: a.averageMacros.fat,
            inRange: a.inRangeCount, under: a.underCount, over: a.overCount, lowNutrients: low)
    }
}

private struct ReflectionSheet: View {
    let input: ReflectionInput
    let reflector: WeeklyReflecting

    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var failed = false

    private var period: String { input.windowLabel.contains("7") ? "week" : "month" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.6), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                SectionEyebrow(text: "Your \(period)")
                if let text {
                    Text(text).font(Theme.Typography.bodyLarge).foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else if failed {
                    Text("Couldn't pull that together just now. Mind trying again in a bit?")
                        .font(Theme.Typography.body).foregroundStyle(Theme.Palette.inkSecondary)
                } else {
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressView().tint(Theme.Palette.accent)
                        Text("Looking back over your \(input.windowLabel)…")
                            .font(Theme.Typography.body).foregroundStyle(Theme.Palette.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
        }
        .background(
            LinearGradient(colors: [Theme.Palette.honey.opacity(0.6), Theme.Palette.background],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .task {
            do { text = try await reflector.reflect(input) }
            catch { failed = true }
        }
    }
}

#Preview {
    TrendsScreen(reflector: MockReflector()).environment(MealStore.sample)
}
