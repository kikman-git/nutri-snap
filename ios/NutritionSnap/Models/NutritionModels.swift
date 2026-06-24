import Foundation

/// How a result was produced (PRD §6). The OCR path lands in v2.
enum NutritionSource: String, Codable, Hashable {
    case vision
    case ocr
}

/// Calm divergent calendar buckets (PRD §5.3) — discrete, never a continuous gradient.
enum DayBand: String, Codable, Hashable, CaseIterable {
    case under
    case inRange = "in"
    case over
    case none

    /// Thresholds are PRD open question #2 (proposed): under <85%, in 85–110%, over >110%.
    static func forKcal(_ kcal: Double, target: Double) -> DayBand {
        guard target > 0, kcal > 0 else { return .none }
        switch kcal / target {
        case ..<0.85:      return .under
        case 0.85...1.10:  return .inRange
        default:           return .over
        }
    }
}

/// Calories + the 3 macros. Used for both logged totals and personal targets (PRD §4).
struct Nutrients: Codable, Hashable {
    var kcal: Double
    var protein: Double   // grams
    var carbs: Double     // grams
    var fat: Double       // grams

    static let zero = Nutrients(kcal: 0, protein: 0, carbs: 0, fat: 0)

    static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(kcal: lhs.kcal + rhs.kcal,
                  protein: lhs.protein + rhs.protein,
                  carbs: lhs.carbs + rhs.carbs,
                  fat: lhs.fat + rhs.fat)
    }
}

/// The "focused 8" nutrients the app tracks for long-term health/beauty (see memory:
/// nutrition-app-direction). Estimated from photos — low-confidence by nature, judged on
/// rolling adequacy over time, never daily pass/fail. Protein lives in `Nutrients`; the other
/// seven ride along in `NutrientAmounts`. Reference intakes are MHLW DRIs, adult-male default
/// until personalized at onboarding (M5).
enum Nutrient: String, CaseIterable, Identifiable, Codable {
    case protein, fiber, omega3, vitaminC, vitaminA, zinc, iron, magnesium

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .protein:   return "Protein"
        case .fiber:     return "Fiber"
        case .omega3:    return "Omega-3"
        case .vitaminC:  return "Vitamin C"
        case .vitaminA:  return "Vitamin A"
        case .zinc:      return "Zinc"
        case .iron:      return "Iron"
        case .magnesium: return "Magnesium"
        }
    }

    var unit: String {
        switch self {
        case .protein, .fiber, .omega3:            return "g"
        case .vitaminC, .zinc, .iron, .magnesium:  return "mg"
        case .vitaminA:                            return "µg"
        }
    }

    /// Daily reference (MHLW adult-male DRI). Protein defers to the user's macro target so the
    /// app shows one protein number everywhere; the rest are static until M5 personalization.
    func referenceDaily(target: Nutrients) -> Double {
        switch self {
        case .protein:   return target.protein
        case .fiber:     return 21
        case .omega3:    return 2.0
        case .vitaminC:  return 100
        case .vitaminA:  return 900
        case .zinc:      return 11
        case .iron:      return 7.5
        case .magnesium: return 370
        }
    }
}

/// A bag of nutrient amounts keyed by `Nutrient.rawValue`. Stored/encoded as a flat object
/// (`{ "fiber": 14, ... }`) so it's clean on the Gemini wire and in Firestore later.
struct NutrientAmounts: Hashable {
    var values: [String: Double]

    static let zero = NutrientAmounts(values: [:])

    init(values: [String: Double] = [:]) { self.values = values }
    init(_ typed: [Nutrient: Double]) {
        values = Dictionary(uniqueKeysWithValues: typed.map { ($0.key.rawValue, $0.value) })
    }

    subscript(_ n: Nutrient) -> Double { values[n.rawValue] ?? 0 }

    static func + (lhs: NutrientAmounts, rhs: NutrientAmounts) -> NutrientAmounts {
        var merged = lhs.values
        for (k, v) in rhs.values { merged[k, default: 0] += v }
        return NutrientAmounts(values: merged)
    }
}

extension NutrientAmounts: Codable {
    init(from decoder: Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: Double].self)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

/// One food the model identified in a photo (PRD §6 contract).
struct FoodItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var portion: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var confidence: Double   // 0...1
}

/// One logged photo → its items, totals and gentle note (mirrors Firestore `entries/{id}`).
struct Entry: Identifiable, Codable, Hashable {
    var id = UUID()
    var capturedAt: Date
    var source: NutritionSource
    var edited: Bool
    var items: [FoodItem]
    var totals: Nutrients
    /// The other seven focused nutrients for this entry (protein is in `totals`).
    var micros: NutrientAmounts = .zero
    var balanceNote: String
    /// MVP placeholder: an SF Symbol name standing in for the real food photo.
    var photoSymbol: String?
    /// Local filename of the saved photo (under Application Support; free tier — Cloud Storage is
    /// M4). Set on save when the write succeeds; nil falls back to a placeholder.
    var photoPath: String? = nil

    /// Low-confidence results invite a tap instead of asserting (PRD §5.2).
    var isLowConfidence: Bool {
        guard let lowest = items.map(\.confidence).min() else { return false }
        return lowest < 0.6
    }
}

/// A single calendar day — mirrors the Firestore `days/{yyyy-MM-dd}` rollup doc (PRD §8).
struct DayLog: Identifiable, Hashable {
    var date: Date
    var entries: [Entry]

    var id: String { DayLog.key(for: date) }
    var entryCount: Int { entries.count }
    var totals: Nutrients { entries.map(\.totals).reduce(.zero, +) }
    var microTotals: NutrientAmounts { entries.reduce(.zero) { $0 + $1.micros } }

    func band(target: Nutrients) -> DayBand {
        DayBand.forKcal(totals.kcal, target: target.kcal)
    }

    /// The tiny precomputed summary the calendar/Trends actually read (see `DayRollup`).
    var rollup: DayRollup {
        DayRollup(date: date, totals: totals, microTotals: microTotals, entryCount: entryCount)
    }

    /// `yyyy-MM-dd` — the Firestore document id and our lookup key.
    static func key(for date: Date) -> String {
        keyFormatter.string(from: date)
    }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// The Firestore `days/{yyyy-MM-dd}` rollup doc (PRD §8): a tiny precomputed per-day summary so the
/// calendar and Trends read one small doc per day instead of querying every meal. Maintained on
/// entry write via offline-safe field increments — the calendar never touches `entries`.
struct DayRollup: Identifiable, Hashable, Codable {
    var date: Date
    var totals: Nutrients
    var microTotals: NutrientAmounts
    var entryCount: Int

    var id: String { DayLog.key(for: date) }

    static func zero(_ date: Date) -> DayRollup {
        DayRollup(date: date, totals: .zero, microTotals: .zero, entryCount: 0)
    }

    func band(target: Nutrients) -> DayBand {
        DayBand.forKcal(totals.kcal, target: target.kcal)
    }
}

extension DayRollup {
    // Tolerate older / edge rollup docs that predate a field — e.g. a day whose meals all had zero
    // micros writes no `microTotals` (rollupDelta omits empty maps), and pre-micros M2 data has none
    // at all. Decode those with sensible defaults instead of throwing, which would silently drop the
    // whole day from the calendar + Trends (the "add more meals" symptom). Encode stays synthesized.
    private enum CodingKeys: String, CodingKey { case date, totals, microTotals, entryCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        totals = try c.decodeIfPresent(Nutrients.self, forKey: .totals) ?? .zero
        microTotals = try c.decodeIfPresent(NutrientAmounts.self, forKey: .microTotals) ?? .zero
        entryCount = try c.decodeIfPresent(Int.self, forKey: .entryCount) ?? 0
    }
}

/// The Firestore `users/{uid}` profile doc (PRD §8). For now only the daily target — seeded with a
/// default on first launch; Mifflin–St Jeor personalization writes it at onboarding (M5).
struct UserProfile: Codable, Hashable {
    var targets: Nutrients
    var createdAt: Date
}
