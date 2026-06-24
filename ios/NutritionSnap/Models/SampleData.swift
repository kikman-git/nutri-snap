import Foundation

/// Fake data for the milestone-1/2 shell (PRD §9, step 1: "zero backend").
/// Everything here is replaced by Firestore reads in milestone 3.
///
/// History is a **rolling ~35-day window relative to today** (not month-anchored) so the
/// Trends tab has continuous data for both the 7- and 30-day views. Deterministic — no
/// `random` — so screenshots and the calendar stay stable across launches.
enum SampleData {
    /// Personal daily target — hardcoded for now; Mifflin–St Jeor arrives in milestone 5.
    /// 2000 kcal at the default 20/50/30 split (PRD §4).
    static let target = Nutrients(kcal: 2000, protein: 100, carbs: 250, fat: 67)

    /// The last ~35 days, seeded with realistic gaps. Backs the day diary + the rollups below.
    static let days: [DayLog] = makeDays()

    /// The per-day rollups the calendar + Trends read (mirrors Firestore `days/{…}`).
    static let rollups: [DayRollup] = days.map(\.rollup)

    /// Most recent entry, for the camera screen's "just logged" card.
    static var recentEntry: Entry? {
        days.flatMap(\.entries).max(by: { $0.capturedAt < $1.capturedAt })
    }

    static func day(for date: Date) -> DayLog? {
        let key = DayLog.key(for: date)
        return days.first { $0.id == key }
    }

    // MARK: - Generation

    private static let historyDays = 35

    private static func makeDays() -> [DayLog] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        return (0..<historyDays).compactMap { offset -> DayLog? in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }

            // Deterministic gap: roughly one un-logged day a week. Real life has gaps —
            // the calendar treats them as "no log yet", never a guilt streak-break.
            if offset != 0, offset % 7 == 5 { return nil }

            let weekday = cal.component(.weekday, from: date)   // 1 = Sun … 7 = Sat
            let isWeekend = weekday == 1 || weekday == 7
            let meals = mealPlan(offset: offset, isWeekend: isWeekend, isToday: offset == 0)
            guard !meals.isEmpty else { return nil }

            let stamped = meals.enumerated().map { idx, meal -> Entry in
                var meal = meal
                meal.capturedAt = cal.date(bySettingHour: 8 + idx * 4, minute: 30, second: 0, of: date) ?? date
                return meal
            }
            return DayLog(date: date, entries: stamped)
        }
    }

    /// Deterministic meal plan per day. Weekends run fuller (so the Trends "weekends tend to
    /// run a little fuller" pattern is real, not invented); today is partial (the day's in progress).
    private static func mealPlan(offset: Int, isWeekend: Bool, isToday: Bool) -> [Entry] {
        if isToday {
            return [breakfast(540), lunch(660)]                                  // ~1200, day in progress
        }
        if isWeekend {
            return [breakfast(600), lunch(880), dinner(950), snack(300)]         // ~2730, a fuller day
        }
        switch offset % 4 {
        case 0:  return [breakfast(520), lunch(640), dinner(700)]               // ~1860, on track
        case 1:  return [breakfast(480), lunch(560)]                            // ~1040, a lighter day
        case 2:  return [breakfast(560), lunch(620), dinner(740), snack(180)]   // ~2100, on track
        default: return [lunch(700), dinner(820)]                              // ~1520, a lighter day
        }
    }

    // MARK: - Meal factories (placeholder food + SF Symbol "photos")
    // Micros are rough per-meal estimates; calibrated so omega-3 + vitamin A read low across the
    // week (a real nudge) while iron lands covered — i.e. the sufficiency view shows a mix.

    private static func breakfast(_ kcal: Double) -> Entry {
        entry(name: "Toast & eggs", portion: "1 plate", kcal: kcal,
              split: (0.20, 0.45, 0.35), note: "A balanced start.",
              symbol: "fork.knife", confidence: 0.82,
              micros: [.fiber: 4, .omega3: 0.1, .vitaminC: 10, .vitaminA: 250,
                       .zinc: 2.5, .iron: 2.5, .magnesium: 95])
    }
    private static func lunch(_ kcal: Double) -> Entry {
        entry(name: "親子丼 / Oyakodon", portion: "1 bowl", kcal: kcal,
              split: (0.22, 0.55, 0.23), note: "Looks balanced.",
              symbol: "takeoutbag.and.cup.and.straw.fill", confidence: 0.55, // low → invites a tap
              micros: [.fiber: 5, .omega3: 0.2, .vitaminC: 40, .vitaminA: 180,
                       .zinc: 3.5, .iron: 3.0, .magnesium: 110])
    }
    private static func dinner(_ kcal: Double) -> Entry {
        entry(name: "Salmon & rice", portion: "1 plate", kcal: kcal,
              split: (0.28, 0.42, 0.30), note: "Good protein tonight.",
              symbol: "fish.fill", confidence: 0.78,
              micros: [.fiber: 5, .omega3: 1.1, .vitaminC: 35, .vitaminA: 140,
                       .zinc: 3.5, .iron: 2.0, .magnesium: 120])
    }
    private static func snack(_ kcal: Double) -> Entry {
        entry(name: "Yogurt & fruit", portion: "1 cup", kcal: kcal,
              split: (0.18, 0.62, 0.20), note: "A light bite.",
              symbol: "cup.and.saucer.fill", confidence: 0.70,
              micros: [.fiber: 3, .omega3: 0.0, .vitaminC: 35, .vitaminA: 90,
                       .zinc: 1.5, .iron: 0.5, .magnesium: 45])
    }

    /// `split` = (protein, carbs, fat) fraction of kcal; grams via 4/4/9 kcal-per-gram.
    private static func entry(name: String, portion: String, kcal: Double,
                              split: (Double, Double, Double), note: String,
                              symbol: String, confidence: Double,
                              micros: [Nutrient: Double]) -> Entry {
        let nutrients = Nutrients(kcal: kcal,
                                  protein: kcal * split.0 / 4,
                                  carbs:   kcal * split.1 / 4,
                                  fat:     kcal * split.2 / 9)
        let item = FoodItem(name: name, portion: portion, kcal: kcal,
                            protein: nutrients.protein, carbs: nutrients.carbs,
                            fat: nutrients.fat, confidence: confidence)
        return Entry(capturedAt: Date(), source: .vision, edited: false,
                     items: [item], totals: nutrients, micros: NutrientAmounts(micros),
                     balanceNote: note, photoSymbol: symbol)
    }
}
