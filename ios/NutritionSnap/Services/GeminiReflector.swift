import Foundation
import FirebaseAI

/// Real "reflect on my week" provider: Firebase AI Logic → Gemini, text in / text out.
/// Same backend setup as `GeminiMealEstimator`; no JSON response type — we want warm prose.
/// One paid call per tap (the user opts in), so it never blocks the charts.
final class GeminiReflector: WeeklyReflecting {
    static let shared = GeminiReflector()

    private let model: GenerativeModel

    private init() {
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        model = ai.generativeModel(
            modelName: "gemini-2.5-flash",
            systemInstruction: ModelContent(role: "system", parts: GeminiPrompt.reflectionSystemInstruction)
        )
    }

    func reflect(_ input: ReflectionInput) async throws -> String {
        let response = try await model.generateContent(GeminiPrompt.reflectionMessage(input))
        guard let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw EstimationError.failed
        }
        return text
    }
}
