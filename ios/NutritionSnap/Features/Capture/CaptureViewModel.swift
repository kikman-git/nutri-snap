import SwiftUI
import UIKit
import Observation

/// Drives the capture screen's calm state machine (PRD §5.2):
/// idle → reviewing → analyzing → logged · notFood · failed. Backed by any `MealEstimating`,
/// so the mock today and the real Gemini call later are interchangeable.
///
/// Capture now pauses on a **review** step: the photo (from the nav-bar shutter or the library)
/// is staged so the person can add an optional note before it's sent. The note is folded into
/// the Gemini prompt. Owns the live `CameraSession`.
@MainActor
@Observable
final class CaptureViewModel {
    enum Phase: Equatable { case idle, reviewing, analyzing, logged, notFood, failed }

    private(set) var phase: Phase = .idle
    private(set) var entry: Entry?
    private(set) var image: UIImage?
    /// JPEG bytes of the staged photo, kept for the estimate call and for persistence.
    private(set) var imageData: Data?
    private(set) var message: String?
    /// The reviewer's optional note — extra context appended to the prompt. Bound by the review UI.
    var note: String = ""
    /// The meal slot, defaulted from the capture hour and overridable by the review "When" chips (D3).
    var selectedSlot: MealSlot = .default(for: Date())
    /// Raised when the server declines a scan on quota/entitlement grounds — the capture screen
    /// presents the gentle paywall. Two-way so the sheet's binding can clear it on dismiss.
    var showPaywall = false
    /// True when the staged photo came from the live camera (vs the library). Camera snaps are
    /// saved to the user's Photos on log; library picks already live there.
    private var fromCamera = false

    let camera = CameraSession()
    private let estimator: MealEstimating

    init(estimator: MealEstimating = MockMealEstimator()) {
        self.estimator = estimator
    }

    // MARK: - Capture → review

    /// Nav-bar shutter: grab a frame from the live camera and stage it for review.
    func shoot() async {
        guard phase != .reviewing, phase != .analyzing else { return }
        do { review(try await camera.capturePhoto(), fromCamera: true) }
        catch { fail(error) }
    }

    /// Stage a freshly captured or picked photo for review (add a note, then confirm).
    func review(_ image: UIImage, fromCamera: Bool = false) {
        self.image = image
        self.fromCamera = fromCamera
        imageData = image.jpegData(compressionQuality: 0.7)
        note = ""
        selectedSlot = .default(for: Date())
        message = nil
        entry = nil
        phase = .reviewing
    }

    /// Discard the staged photo and return to the live viewfinder.
    func retake() { reset() }

    // MARK: - Review → analyze → persist

    /// Send the staged photo (plus any note) to the estimator, then persist a successful log.
    func confirm(into store: MealStore) async {
        guard phase == .reviewing, let imageData else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        message = nil
        phase = .analyzing
        do {
            let meal = try await estimator.estimate(imageData: imageData,
                                                    note: trimmed.isEmpty ? nil : trimmed)
            if meal.isFood {
                let entry = meal.asEntry(slot: selectedSlot)
                self.entry = entry
                phase = .logged
                try? await store.save(entry, imageData: imageData)
                // A meal snapped in-app is saved to Photos too (best-effort, silent).
                if fromCamera, let image { await PhotoLibrarySaver.save(image) }
            } else {
                entry = nil
                message = meal.balanceNote
                phase = .notFood
            }
        } catch EstimationError.quotaReached {
            // Quota/entitlement decline. Don't show an error — keep the staged photo + note on the
            // review step and raise the gentle paywall. If they're *already* subscribed, the
            // server's entitlement mirror (RevenueCat webhook → plan/current) is just lagging a
            // beat; say so calmly and let them retry rather than re-show the paywall.
            phase = .reviewing
            if SubscriptionStore.shared.isSubscribed {
                message = "You're all set — activating your subscription. Tap Analyze again in a moment."
            } else {
                showPaywall = true
            }
        } catch {
            fail(error)
        }
    }

    func reset() {
        phase = .idle; entry = nil; image = nil; imageData = nil; message = nil; note = ""; fromCamera = false
    }

    func replaceLoggedEntry(_ updated: Entry) {
        guard phase == .logged, entry?.id == updated.id else { return }
        entry = updated
    }

    private func fail(_ error: Error) {
        #if DEBUG
        // Show the real error on-device while debugging (e.g. App Check 403); release stays gentle.
        message = (error as? EstimationError)?.errorDescription ?? String(describing: error)
        #else
        message = (error as? LocalizedError)?.errorDescription
            ?? "We couldn't quite read that one. Mind trying again?"
        #endif
        phase = .failed
    }
}
