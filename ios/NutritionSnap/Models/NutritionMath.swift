import Foundation

/// Personal nutrition math (PRD §4) — Mifflin–St Jeor for energy plus a fixed macro split.
/// Deliberately locale-agnostic: no national calorie tables, just the user's body stats. Used at
/// onboarding (M5) to turn a `UserProfile` into the daily `target` the calendar + Trends compare
/// against. Pure and UIKit-free, so it lives with the models and stays unit-testable.
enum NutritionMath {

    /// Mifflin–St Jeor basal metabolic rate. W=kg, H=cm, A=years (PRD §4).
    static func bmr(sex: BiologicalSex, age: Int, heightCm: Double, weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return base + (sex == .male ? 5 : -161)
    }

    /// The personal daily target: BMR × activity × goal, split 20/50/30 into protein/carbs/fat
    /// grams (4/4/9 kcal per gram). kcal is tidied to the nearest 10 so the UI reads cleanly.
    static func target(for p: UserProfile) -> Nutrients {
        let tdee = bmr(sex: p.sex, age: p.age, heightCm: p.heightCm, weightKg: p.weightKg)
            * p.activity.factor * p.goal.factor
        let kcal = max((tdee / 10).rounded() * 10, 0)
        return Nutrients(kcal: kcal,
                         protein: (kcal * 0.20 / 4).rounded(),
                         carbs:   (kcal * 0.50 / 4).rounded(),
                         fat:     (kcal * 0.30 / 9).rounded())
    }

    /// Daily reference intakes for the focused 8 (MHLW 2020 DRIs, adult). Sex is the main driver —
    /// iron, zinc, vitamin A and magnesium differ — so women aren't judged against male numbers.
    /// Protein follows the user's macro target so the app shows one protein figure everywhere.
    /// Age-banding is a later refinement. Returned as `NutrientAmounts` so it threads next to totals.
    static func microReferences(sex: BiologicalSex, proteinTarget: Double) -> NutrientAmounts {
        let male = sex == .male
        return NutrientAmounts([
            .protein:   proteinTarget,
            .fiber:     male ? 21  : 18,
            .omega3:    male ? 2.0 : 1.6,
            .vitaminC:  100,
            .vitaminA:  male ? 900 : 700,
            .zinc:      male ? 11  : 8,
            .iron:      male ? 7.5 : 10.5,   // menstruating women need more
            .magnesium: male ? 370 : 290,
        ])
    }
}
