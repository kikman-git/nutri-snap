import Foundation

/// The seam for the opt-in "reflect on my week" narrative (Trends tab). Distinct from
/// `MealEstimating`: this is a *text* call (recent aggregates → a warm paragraph), made only
/// when the user taps — charts/numbers never wait on the network. `GeminiReflector` is real;
/// `MockReflector` backs previews/screenshots. One paid call per tap (cost-aware, PRD §6).
protocol WeeklyReflecting {
    func reflect(_ input: ReflectionInput) async throws -> String
}

/// The aggregates handed to the reflector — already summarized, so no raw history leaves the app.
struct ReflectionInput: Hashable {
    var windowLabel: String     // "7 days" / "30 days"
    var loggedDays: Int
    var avgKcal: Double
    var target: Nutrients
    var avgProtein: Double
    var avgCarbs: Double
    var avgFat: Double
    var inRange: Int
    var under: Int
    var over: Int
    var lowNutrients: [String]    // display names running low on the rolling average
}

/// Canned warm reflection for previews/screenshots — no network, deterministic.
struct MockReflector: WeeklyReflecting {
    func reflect(_ input: ReflectionInput) async throws -> String {
        try? await Task.sleep(for: .milliseconds(900))
        return """
        This past \(input.windowLabel.contains("7") ? "week" : "month") looked gentle and \
        steady — you showed up and logged \(input.loggedDays) days, which is the part that \
        really counts. Your meals leaned gently balanced, with a few fuller days mixed in; \
        that's just life, and nothing to undo. Keep snapping when it's easy — the rhythm is \
        already here.
        """
    }
}
