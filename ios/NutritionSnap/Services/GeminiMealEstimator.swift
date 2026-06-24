import Foundation
import FirebaseAI
import OSLog

/// Real estimator: Firebase AI Logic → Gemini (Gemini Developer API backend). Same `MealEstimating`
/// seam as the mock, so the UI is unchanged. Shared singleton so the model isn't rebuilt per view.
final class GeminiMealEstimator: MealEstimating {
    static let shared = GeminiMealEstimator()

    private let model: GenerativeModel
    private let log = Logger(subsystem: "com.kikman.nutrisnap", category: "Gemini")

    private init() {
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())   // .vertexAI() to switch backends
        model = ai.generativeModel(
            modelName: "gemini-2.5-flash",
            // 2.5-flash is a thinking model: reasoning tokens share the output budget, and for a
            // photo→JSON extraction they were burning ~2000 tokens and truncating the JSON
            // (MAX_TOKENS). Cap thinking low and give the body real headroom — also cheaper/faster
            // at ~100–150 calls/user/month (PRD §6). JSON response type keeps the body parseable.
            generationConfig: GenerationConfig(maxOutputTokens: 4096,
                                               responseMIMEType: "application/json",
                                               thinkingConfig: ThinkingConfig(thinkingBudget: 256)),
            systemInstruction: ModelContent(role: "system", parts: GeminiPrompt.systemInstruction)
        )
    }

    func estimate(imageData: Data, note: String?) async throws -> EstimatedMeal {
        let image = InlineDataPart(data: imageData, mimeType: "image/jpeg")
        var prompt = GeminiPrompt.jsonContract
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            prompt += "\n\n" + GeminiPrompt.userNote(note)
        }
        do {
            let response = try await model.generateContent(prompt, image)
            guard let text = response.text, let data = text.data(using: .utf8) else {
                log.error("Gemini returned no usable text")
                throw EstimationError.failed
            }
            do {
                let meal = try JSONDecoder().decode(EstimatedMeal.self, from: data)
                log.debug("Gemini ok: \(meal.items.count) items · \(Int(meal.resolvedTotals.kcal)) kcal · P\(Int(meal.resolvedTotals.protein))g · micros=\(String(describing: meal.micros?.values), privacy: .public)")
                return meal
            } catch {
                log.error("Gemini JSON decode failed: \(String(describing: error), privacy: .public)\nbody: \(text, privacy: .public)")
                throw EstimationError.failed
            }
        } catch let error as EstimationError {
            throw error                                     // already logged above
        } catch {
            // Real Firebase / App Check / network error — the usual device culprit is an
            // App Check 403 (the device's debug token isn't registered). Surfaced in the console.
            log.error("Gemini request failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }
}
