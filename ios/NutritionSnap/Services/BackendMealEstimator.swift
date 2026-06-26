import Foundation
import FirebaseFunctions
import OSLog

/// Production estimator: sends the photo to the `scanMeal` Cloud Function — the *only* path to
/// Gemini now. The backend verifies Auth + App Check + entitlement + quota and calls Gemini
/// server-side (the key lives in Secret Manager, never in the app), so a modified client can't
/// run up the LLM bill. Same `MealEstimating` seam as `MockMealEstimator` and the now dev-only
/// on-device `GeminiMealEstimator`, so the capture UI is unchanged.
final class BackendMealEstimator: MealEstimating {
    static let shared = BackendMealEstimator()

    private lazy var functions = Functions.functions(region: "us-central1")
    private let log = Logger(subsystem: "com.kikman.nutrisnap", category: "Backend")

    func estimate(imageData: Data, note: String?) async throws -> EstimatedMeal {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: Any] = [
            "imageBase64": imageData.base64EncodedString(),
            "mimeType": "image/jpeg",
            "note": trimmed?.isEmpty == false ? trimmed! : "",
            "scanType": "meal_photo",
        ]

        do {
            let result = try await functions.httpsCallable("scanMeal").call(payload)
            guard let dict = result.data as? [String: Any], let meal = dict["meal"] else {
                log.error("scanMeal: response missing `meal`")
                throw EstimationError.failed
            }
            let data = try JSONSerialization.data(withJSONObject: meal)
            let estimated = try JSONDecoder().decode(EstimatedMeal.self, from: data)
            // Surface the server-authoritative free-scan count for the gentle "N left" UI. `null`
            // (a paid tier) decodes to nil → unlimited within the monthly cap.
            let remaining = (dict["remainingFreeScans"] as? NSNumber)?.intValue
            await MainActor.run { SubscriptionStore.shared.noteRemainingFreeScans(remaining) }
            log.debug("scanMeal ok · remaining free: \(remaining.map(String.init) ?? "n/a", privacy: .public)")
            return estimated
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            // Map the backend's gentle rejections. Over free quota / no entitlement → paywall;
            // unauthenticated/unavailable network → offline-ish gentle retry.
            switch FunctionsErrorCode(rawValue: error.code) {
            case .resourceExhausted:
                // Free taste used up — reflect 0 left so the UI is honest before the paywall.
                await MainActor.run { SubscriptionStore.shared.noteRemainingFreeScans(0) }
                throw EstimationError.quotaReached
            case .permissionDenied:
                throw EstimationError.quotaReached
            case .unavailable, .deadlineExceeded:
                throw EstimationError.offline
            default:
                log.error("scanMeal failed: \(error.localizedDescription, privacy: .public)")
                throw EstimationError.failed
            }
        } catch let error as EstimationError {
            throw error
        } catch {
            log.error("scanMeal failed: \(String(describing: error), privacy: .public)")
            throw EstimationError.failed
        }
    }
}
