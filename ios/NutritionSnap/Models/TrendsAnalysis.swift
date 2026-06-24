import Foundation

/// Pure, on-device insights over logged history (Trends tab). No SwiftUI/UIKit — it works on the
/// tiny per-day `[DayRollup]` summaries, whether seeded from `SampleData` or read from Firestore.
///
/// Tone is a hard constraint (PRD §2): patterns are **observational, never judgmental**
/// ("weekends tend to run fuller", not "you overeat on weekends"). Nutrient adequacy is judged
/// on the **rolling window average vs reference**, never a daily pass/fail (see memory:
/// nutrition-app-direction).
struct TrendsAnalysis {
    enum Window: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        var id: Int { rawValue }
        var label: String { self == .week ? "7 days" : "30 days" }
        /// "week" / "month" for prose.
        var period: String { self == .week ? "week" : "month" }
    }

    /// One logged day's calories, bucketed by the same calm band the calendar uses.
    struct DailyPoint: Identifiable, Hashable {
        let date: Date
        let kcal: Double
        let band: DayBand
        var id: Date { date }
    }

    /// How a nutrient's rolling average sits against its reference — gentle, three-state.
    enum Sufficiency {
        case low, close, covered

        static func from(_ ratio: Double) -> Sufficiency {
            if ratio >= 1.0 { return .covered }
            if ratio >= 0.7 { return .close }
            return .low
        }

        var label: String {
            switch self {
            case .low:     return "a bit low"
            case .close:   return "almost there"
            case .covered: return "covered"
            }
        }
    }

    let window: Window
    let target: Nutrients
    let points: [DailyPoint]              // logged days within the window, oldest → newest
    let loggedDayCount: Int
    let averageKcal: Double
    let averageMacros: Nutrients          // average grams per logged day
    let nutrientAverages: [Nutrient: Double]   // average amount per logged day, per focused nutrient
    let inRangeCount: Int
    let underCount: Int
    let overCount: Int
    let patterns: [String]                // gentle, observational callouts
    let summary: String                   // one warm sentence (computed, always-available)

    /// Trends need a few logged *days* before charts are meaningful (many meals in one day is still
    /// one day). Under this, the tab shows a gentle progress nudge instead of noisy charts.
    static let minDaysForTrends = 4
    var hasEnoughData: Bool { loggedDayCount >= Self.minDaysForTrends }

    /// The calm "in range" zone (PRD §5.3 thresholds) for the trend chart's reference band.
    var targetBandLow: Double { target.kcal * 0.85 }
    var targetBandHigh: Double { target.kcal * 1.10 }

    /// Rolling average ÷ reference for a nutrient (1.0 = exactly meeting the reference).
    func adequacy(_ n: Nutrient) -> Double {
        let ref = n.referenceDaily(target: target)
        guard ref > 0 else { return 0 }
        return (nutrientAverages[n] ?? 0) / ref
    }

    func sufficiency(_ n: Nutrient) -> Sufficiency { .from(adequacy(n)) }

    // MARK: - Compute

    static func compute(days: [DayRollup], target: Nutrients,
                        window: Window, now: Date = Date()) -> TrendsAnalysis {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(window.rawValue - 1),
                             to: cal.startOfDay(for: now)) ?? now

        let logged = days
            .filter { $0.entryCount > 0 && $0.date >= start }
            .sorted { $0.date < $1.date }

        let points = logged.map {
            DailyPoint(date: $0.date, kcal: $0.totals.kcal, band: $0.band(target: target))
        }
        let count = logged.count
        let denom = Double(max(count, 1))            // guard ÷0; split out so the type-checker is happy
        let totalKcal = logged.reduce(0.0) { $0 + $1.totals.kcal }
        let avgKcal = count > 0 ? totalKcal / denom : 0

        let macroSum = logged.reduce(Nutrients.zero) { $0 + $1.totals }
        let avgMacros: Nutrients = count > 0
            ? Nutrients(kcal: avgKcal,
                        protein: macroSum.protein / denom,
                        carbs:   macroSum.carbs   / denom,
                        fat:     macroSum.fat     / denom)
            : .zero

        let nutrientAverages = Self.nutrientAverages(logged: logged, count: count)

        let inRange = points.filter { $0.band == .inRange }.count
        let under   = points.filter { $0.band == .under }.count
        let over    = points.filter { $0.band == .over }.count

        return TrendsAnalysis(
            window: window,
            target: target,
            points: points,
            loggedDayCount: count,
            averageKcal: avgKcal,
            averageMacros: avgMacros,
            nutrientAverages: nutrientAverages,
            inRangeCount: inRange,
            underCount: under,
            overCount: over,
            patterns: makePatterns(logged: logged, nutrientAverages: nutrientAverages,
                                   target: target, cal: cal),
            summary: makeSummary(count: count, window: window, inRange: inRange,
                                 avgKcal: avgKcal, target: target))
    }

    // MARK: - Per-nutrient averages

    private static func nutrientAverages(logged: [DayRollup], count: Int) -> [Nutrient: Double] {
        guard count > 0 else { return [:] }
        let denom = Double(count)
        var out: [Nutrient: Double] = [:]
        for n in Nutrient.allCases {
            let total = n == .protein
                ? logged.reduce(0.0) { $0 + $1.totals.protein }
                : logged.reduce(0.0) { $0 + $1.microTotals[n] }
            out[n] = total / denom
        }
        return out
    }

    // MARK: - Gentle copy

    private static func makePatterns(logged: [DayRollup], nutrientAverages: [Nutrient: Double],
                                     target: Nutrients, cal: Calendar) -> [String] {
        var out: [String] = []

        // Weekend vs weekday rhythm (only if we've seen both).
        let weekend = logged.filter { isWeekend($0.date, cal) }.map(\.totals.kcal)
        let weekday = logged.filter { !isWeekend($0.date, cal) }.map(\.totals.kcal)
        if !weekend.isEmpty, !weekday.isEmpty {
            let we = weekend.reduce(0, +) / Double(weekend.count)
            let wd = weekday.reduce(0, +) / Double(weekday.count)
            if we > wd * 1.15 { out.append("Weekends tend to run a little fuller.") }
            else if wd > we * 1.15 { out.append("Weekdays tend to run a little fuller.") }
        }

        // Nutrients running low on the rolling average — the gentle nudge (not protein; it has its row).
        let low = Nutrient.allCases
            .filter { $0 != .protein }
            .map { ($0, ($0.referenceDaily(target: target) > 0
                        ? (nutrientAverages[$0] ?? 0) / $0.referenceDaily(target: target) : 1)) }
            .filter { $0.1 < 0.7 }
            .sorted { $0.1 < $1.1 }
            .prefix(2)
            .map(\.0.displayName)
        if !low.isEmpty {
            let names = low.joined(separator: " and ")
            out.append("\(names) \(low.count > 1 ? "have" : "has") been on the lighter side lately.")
        }

        // Consistency, as encouragement.
        if logged.count >= 5 {
            out.append("You've logged \(logged.count) days — a lovely habit forming.")
        }

        return Array(out.prefix(3))
    }

    private static func makeSummary(count: Int, window: Window, inRange: Int,
                                    avgKcal: Double, target: Nutrients) -> String {
        guard count > 0 else { return "" }
        let period = window.period
        if Double(inRange) >= Double(count) * 0.6 {
            return "Most days this \(period) landed on track — a lovely rhythm."
        }
        if avgKcal < target.kcal * 0.85 {
            return "A lighter \(period) overall. No pressure — just what the days held."
        }
        if avgKcal > target.kcal * 1.10 {
            return "A fuller \(period) than usual. Every \(period)'s a little different."
        }
        return "A pretty balanced \(period), give or take."
    }

    private static func isWeekend(_ date: Date, _ cal: Calendar) -> Bool {
        let wd = cal.component(.weekday, from: date)
        return wd == 1 || wd == 7
    }
}
