import Foundation

/// Curated everyday-food ideas for the Fill-the-Gaps screen (Warm Bloom §3.4). Bundled static
/// data — no API. The boosts are deliberately rough, illustrative "a bit more" cues, not precise
/// figures; the screen says so. Honest + gentle, matching the brand (no supplement push).
struct FoodSuggestion: Identifiable, Hashable {
    var id: String { name }
    let emoji: String
    let name: String
    let boost: String
}

enum NutrientFoods {
    static func suggestions(for n: Nutrient) -> [FoodSuggestion] { table[n] ?? [] }
    static func tip(for n: Nutrient) -> String? { tips[n] }

    /// Short chemical/vitamin code for the round badge (calm, no long labels).
    static func code(_ n: Nutrient) -> String {
        switch n {
        case .protein:   return "Pro"
        case .fiber:     return "Fbr"
        case .omega3:    return "ω3"
        case .vitaminC:  return "C"
        case .vitaminA:  return "A"
        case .vitaminD:  return "D"
        case .b12:       return "B12"
        case .folate:    return "B9"
        case .zinc:      return "Zn"
        case .iron:      return "Fe"
        case .magnesium: return "Mg"
        case .potassium: return "K"
        }
    }

    private static let table: [Nutrient: [FoodSuggestion]] = [
        .magnesium: [.init(emoji: "🥬", name: "Spinach", boost: "+20%"),
                     .init(emoji: "🎃", name: "Pumpkin seeds", boost: "+25%"),
                     .init(emoji: "🍫", name: "Dark choc", boost: "+15%")],
        .fiber:     [.init(emoji: "🫘", name: "Black beans", boost: "+7g"),
                     .init(emoji: "🍐", name: "Pear", boost: "+5g"),
                     .init(emoji: "🥑", name: "Avocado", boost: "+6g")],
        .iron:      [.init(emoji: "🥩", name: "Red meat", boost: "+25%"),
                     .init(emoji: "🥬", name: "Spinach", boost: "+12%"),
                     .init(emoji: "🫘", name: "Lentils", boost: "+18%")],
        .zinc:      [.init(emoji: "🦪", name: "Oysters", boost: "+40%"),
                     .init(emoji: "🎃", name: "Pumpkin seeds", boost: "+15%"),
                     .init(emoji: "🥩", name: "Beef", boost: "+20%")],
        .vitaminC:  [.init(emoji: "🍊", name: "Orange", boost: "+60%"),
                     .init(emoji: "🫑", name: "Bell pepper", boost: "+90%"),
                     .init(emoji: "🥦", name: "Broccoli", boost: "+45%")],
        .vitaminA:  [.init(emoji: "🥕", name: "Carrots", boost: "+50%"),
                     .init(emoji: "🍠", name: "Sweet potato", boost: "+40%"),
                     .init(emoji: "🥬", name: "Spinach", boost: "+30%")],
        .omega3:    [.init(emoji: "🐟", name: "Salmon", boost: "+1.2g"),
                     .init(emoji: "🌰", name: "Walnuts", boost: "+0.5g"),
                     .init(emoji: "🥄", name: "Chia seeds", boost: "+0.8g")],
        .potassium: [.init(emoji: "🍌", name: "Banana", boost: "+12%"),
                     .init(emoji: "🥔", name: "Potato", boost: "+18%"),
                     .init(emoji: "🫘", name: "Beans", boost: "+15%")],
        .vitaminD:  [.init(emoji: "🐟", name: "Salmon", boost: "+80%"),
                     .init(emoji: "🥚", name: "Egg yolk", boost: "+10%"),
                     .init(emoji: "🍄", name: "Mushrooms", boost: "+15%")],
        .b12:       [.init(emoji: "🐟", name: "Fish", boost: "+90%"),
                     .init(emoji: "🥚", name: "Eggs", boost: "+25%"),
                     .init(emoji: "🥛", name: "Dairy", boost: "+30%")],
        .folate:    [.init(emoji: "🥬", name: "Leafy greens", boost: "+40%"),
                     .init(emoji: "🫘", name: "Lentils", boost: "+45%"),
                     .init(emoji: "🥑", name: "Avocado", boost: "+20%")],
        .protein:   [.init(emoji: "🍗", name: "Chicken", boost: "+25g"),
                     .init(emoji: "🥚", name: "Eggs", boost: "+12g"),
                     .init(emoji: "🫛", name: "Tofu", boost: "+10g")],
    ]

    private static let tips: [Nutrient: String] = [
        .magnesium: "A handful of pumpkin seeds tonight covers most of it.",
        .fiber:     "Keeping the skin on fruit or adding beans goes a long way.",
        .iron:      "Pair greens with a squeeze of citrus to absorb more.",
        .zinc:      "A small handful of seeds is an easy daily top-up.",
        .vitaminC:  "One piece of fruit usually covers the whole day.",
        .vitaminA:  "Cooked carrots or sweet potato are rich and easy.",
        .omega3:    "Oily fish a couple of times a week keeps this topped up.",
        .potassium: "Most veg and fruit chip away at this nicely.",
        .vitaminD:  "A little midday sun helps as much as food does.",
        .b12:       "Animal foods cover this; supplement if you're plant-based.",
        .folate:    "A leafy side salad is a simple win.",
    ]
}
