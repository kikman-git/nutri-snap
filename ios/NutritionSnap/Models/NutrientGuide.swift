import Foundation

/// Educational daily-needs reference shown in Journal, so you can target food or supplements.
/// Pure data (no SwiftUI). Covers the focused 8 the app estimates (`tracked`) plus the common
/// supplement-worthy ones it can't read from a photo (log those via supplements / bloodwork).
/// Amounts are general adult guidance (Japanese MHLW DRI) — not medical advice.
struct NutrientGuideEntry: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case macrosFats = "Protein, fiber & fats"
        case vitamins   = "Vitamins"
        case minerals   = "Minerals"
        var id: String { rawValue }
    }

    let name: String
    let dailyAmount: String   // e.g. "100 mg"
    let benefit: String       // why it matters (skin/hair/gut framing)
    let sources: String       // good food sources
    let category: Category
    let tracked: Bool         // does the app estimate it from photos?

    var id: String { name }
}

enum NutrientGuide {
    static func entries(in category: NutrientGuideEntry.Category) -> [NutrientGuideEntry] {
        all.filter { $0.category == category }
    }

    static let all: [NutrientGuideEntry] = [
        // Protein, fiber & fats — all tracked.
        .init(name: "Protein", dailyAmount: "65 g",
              benefit: "Skin, hair & muscle building blocks",
              sources: "Fish, meat, eggs, tofu, beans", category: .macrosFats, tracked: true),
        .init(name: "Fiber", dailyAmount: "21 g",
              benefit: "Gut health & steady digestion",
              sources: "Veg, whole grains, legumes", category: .macrosFats, tracked: true),
        .init(name: "Omega-3", dailyAmount: "2.0 g",
              benefit: "Skin barrier, anti-inflammatory",
              sources: "Oily fish, walnuts, flaxseed", category: .macrosFats, tracked: true),

        // Vitamins.
        .init(name: "Vitamin A", dailyAmount: "900 µg",
              benefit: "Skin renewal & eyes",
              sources: "Liver, carrots, spinach, egg", category: .vitamins, tracked: true),
        .init(name: "Vitamin C", dailyAmount: "100 mg",
              benefit: "Collagen for skin, immunity",
              sources: "Citrus, peppers, broccoli", category: .vitamins, tracked: true),
        .init(name: "Vitamin D", dailyAmount: "8.5 µg",
              benefit: "Bone, immune, hair — often runs low",
              sources: "Sun, salmon, egg yolk · supplement common", category: .vitamins, tracked: true),
        .init(name: "Vitamin E", dailyAmount: "6.0 mg",
              benefit: "Skin antioxidant",
              sources: "Nuts, seeds, vegetable oils", category: .vitamins, tracked: false),
        .init(name: "Vitamin B12", dailyAmount: "2.4 µg",
              benefit: "Energy, hair, nerves",
              sources: "Fish, meat, eggs · vegans supplement", category: .vitamins, tracked: true),
        .init(name: "Folate (B9)", dailyAmount: "240 µg",
              benefit: "Cell renewal",
              sources: "Leafy greens, legumes", category: .vitamins, tracked: true),

        // Minerals.
        .init(name: "Iron", dailyAmount: "7.5 mg",
              benefit: "Hair & energy (hair thins if low)",
              sources: "Red meat, spinach, lentils", category: .minerals, tracked: true),
        .init(name: "Zinc", dailyAmount: "11 mg",
              benefit: "Skin healing & hair",
              sources: "Oysters, meat, pumpkin seeds", category: .minerals, tracked: true),
        .init(name: "Magnesium", dailyAmount: "370 mg",
              benefit: "Sleep, muscle, calm",
              sources: "Nuts, greens, whole grains", category: .minerals, tracked: true),
        .init(name: "Potassium", dailyAmount: "2500 mg",
              benefit: "Blood pressure, muscle & nerves",
              sources: "Veg, fruit, beans, potato", category: .minerals, tracked: true),
        .init(name: "Calcium", dailyAmount: "750 mg",
              benefit: "Bone strength",
              sources: "Dairy, tofu, small fish", category: .minerals, tracked: false),
        .init(name: "Selenium", dailyAmount: "30 µg",
              benefit: "Thyroid & skin antioxidant",
              sources: "Fish, eggs, brazil nuts", category: .minerals, tracked: false),
        .init(name: "Iodine", dailyAmount: "130 µg",
              benefit: "Thyroid → hair & skin",
              sources: "Seaweed, fish", category: .minerals, tracked: false),
    ]
}
