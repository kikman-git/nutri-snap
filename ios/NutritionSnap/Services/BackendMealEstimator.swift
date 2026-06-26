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
            if let remaining = dict["remainingFreeScans"] as? Int {
                log.debug("scanMeal ok · remaining free: \(remaining)")
            }
            return estimated
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            // Map the backend's gentle rejections. Over free quota / no entitlement → paywall;
            // unauthenticated/unavailable network → offline-ish gentle retry.
            switch FunctionsErrorCode(rawValue: error.code) {
            case .resourceExhausted, .permissionDenied:
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
