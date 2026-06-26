import Foundation

/// Stand-in for the real Firebase AI Logic → Gemini call (PRD §6). Returns the §6 contract
/// after a short, realistic delay so the capture flow feels real before Firebase is wired.
/// `MOCK_RESULT` forces a specific outcome (used for headless state screenshots).
final class MockMealEstimator: MealEstimating {
    func estimate(imageData: Data, note: String?) async throws -> EstimatedMeal {
        // MOCK_SLOW lengthens the delay so the "reading…" state can be screenshotted headlessly.
        let seconds = ProcessInfo.processInfo.environment["MOCK_SLOW"] != nil ? 6.0 : 1.4
        try? await Task.sleep(for: .seconds(seconds))   // let the "reading…" state breathe

        switch ProcessInfo.processInfo.environment["MOCK_RESULT"] {
        case "error":   throw EstimationError.failed
        case "offline": throw EstimationError.offline
        case "notfood": return .notFoodSample
        case "lowconf": return .oyakodonLowConfidence
        case "happy":   return .salmonAndRice
        default:        return Self.plausible.randomElement() ?? .toastAndEggs
        }
    }

    /// Happy-path variety, including one genuinely low-confidence result so the
    /// "Tap to confirm" path appears naturally (PRD §5.2).
    private static let plausible: [EstimatedMeal] = [
        .toastAndEggs, .salmonAndRice, .saladBowl, .oyakodonLowConfidence,
    ]
}

// MARK: - Fixtures (mirror the wire contract)

private extension EstimatedMeal {
    /// `split` = (protein, carbs, fat) fraction of kcal; grams via 4/4/9 kcal-per-gram.
    static func make(_ name: String, portion: String, kcal: Double,
                     split: (Double, Double, Double), note: String,
                     confidence: Double, micros: [Nutrient: Double] = [:],
                     energy: EnergyShape? = nil) -> EstimatedMeal {
        let item = EstimatedItem(name: name, portion: portion, kcal: kcal,
                                 protein: kcal * split.0 / 4,
                                 carbs:   kcal * split.1 / 4,
                                 fat:     kcal * split.2 / 9,
                                 confidence: confidence)
        return EstimatedMeal(items: [item],
                             totals: Nutrients(kcal: item.kcal, protein: item.protein,
                                               carbs: item.carbs, fat: item.fat),
                             micros: NutrientAmounts(micros),
                             energy: energy,
                             balanceNote: note, source: .vision, notFood: false)
    }

    // Whole-meal micro estimates (rough, like the real call) so the breakdown + Trends look real.
    // Micros cover the focused-12 (+ potassium/vitaminD/b12/folate); energy is the wordless read (D1).
    static let toastAndEggs  = make("Toast & eggs", portion: "1 plate", kcal: 520,
                                    split: (0.20, 0.45, 0.35), note: "A balanced start.", confidence: 0.86,
                                    micros: [.fiber: 3, .omega3: 0.2, .vitaminC: 1, .vitaminA: 180,
                                             .zinc: 1.6, .iron: 2.8, .magnesium: 40,
                                             .potassium: 260, .vitaminD: 1.0, .b12: 0.8, .folate: 45],
                                    energy: .gentleRise)
    static let salmonAndRice = make("Salmon & rice", portion: "1 plate", kcal: 680,
                                    split: (0.30, 0.42, 0.28), note: "Good protein here.", confidence: 0.81,
                                    micros: [.fiber: 2, .omega3: 2.2, .vitaminC: 3, .vitaminA: 60,
                                             .zinc: 1.0, .iron: 1.5, .magnesium: 55,
                                             .potassium: 520, .vitaminD: 8.0, .b12: 3.0, .folate: 30],
                                    energy: .gentleRise)
    static let saladBowl     = make("Chicken salad bowl", portion: "1 bowl", kcal: 430,
                                    split: (0.35, 0.40, 0.25), note: "Light and fresh.", confidence: 0.79,
                                    micros: [.fiber: 6, .omega3: 0.3, .vitaminC: 35, .vitaminA: 420,
                                             .zinc: 1.4, .iron: 2.0, .magnesium: 60,
                                             .potassium: 600, .vitaminD: 0.2, .b12: 0.4, .folate: 80],
                                    energy: .steady)
    /// confidence < 0.6 → routes to the gentle "Tap to confirm" card.
    static let oyakodonLowConfidence = make("親子丼 / Oyakodon", portion: "1 bowl", kcal: 660,
                                    split: (0.22, 0.55, 0.23), note: "Looks balanced.", confidence: 0.5,
                                    micros: [.fiber: 2, .omega3: 0.2, .vitaminC: 4, .vitaminA: 120,
                                             .zinc: 2.0, .iron: 2.2, .magnesium: 50,
                                             .potassium: 360, .vitaminD: 0.9, .b12: 0.9, .folate: 55],
                                    energy: .spike)

    static let notFoodSample = EstimatedMeal(items: [], totals: .zero,
                                             balanceNote: "Hmm, I couldn't find a meal here.",
                                             source: .vision, notFood: true)
}
