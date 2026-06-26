import Foundation
import Observation
import OSLog
import RevenueCat
import FirebaseAuth
import FirebaseFirestore

/// Result of a purchase/restore attempt, mapped to gentle UI outcomes (PRD positioning).
enum PurchaseOutcome { case subscribed, cancelled, failed }

/// The client's **UX** layer over RevenueCat — the paywall's data source and the purchase/restore
/// flow. It does *not* enforce anything.
///
/// ⚠️ Enforcement is server-side: `scanMeal` is the only path to Gemini and it checks quota +
/// entitlement against `users/{uid}/plan/current` (written *only* by the RevenueCat webhook; the
/// client has read-only access per `firestore.rules`). A tampered client that flips `isSubscribed`
/// gains nothing — the backend still rejects unentitled paid scans. This store just decides what
/// the *UI* shows and lets the user buy/restore.
///
/// **Identity rule (load-bearing):** RevenueCat's `appUserID` MUST equal the Firebase uid. The
/// webhook keys entitlement on `app_user_id`, and the backend reads it per-uid — if the two
/// identities diverged, a purchase would never reach the right account. We follow Firebase auth
/// and `logIn(uid)` so they stay in lockstep.
@MainActor
@Observable
final class SubscriptionStore {
    static let shared = SubscriptionStore()

    /// Must match the entitlement identifier configured in the RevenueCat dashboard.
    static let entitlementID = "premium"
    /// The offering the paywall renders; falls back to the dashboard's "current" if absent.
    static let offeringID = "default"
    /// Mirrors `functions/src/config.ts` → `freeLifetimeLimit`. Used only to render the remaining
    /// count from the server-owned quota doc; the server is still the authority.
    static let freeLifetimeLimit = 3

    /// Entitlement state for the UI (subscribed → hide the paywall, show "Premium").
    private(set) var isSubscribed = false
    /// The offering whose packages the paywall shows (Monthly + Annual).
    private(set) var offering: Offering?
    /// Free scans left in the lifetime taste, from the server-owned quota. `nil` = unknown.
    private(set) var remainingFreeScans: Int?
    /// True only after a successful `configure()` (i.e. an API key was present).
    private(set) var isConfigured = false
    /// A purchase or restore is in flight — drives the paywall's button spinner.
    private(set) var actionInFlight = false

    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var infoTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.kikman.nutrisnap", category: "Subscriptions")

    private init() {}

    // MARK: - Configuration

    /// Configure RevenueCat once. Safe to call repeatedly. A **no-op without an API key** (previews,
    /// dev without the env var) so the app still runs — the paywall just shows an unavailable state.
    func configure() {
        guard !isConfigured, let key = RevenueCatConfig.apiKey else {
            if RevenueCatConfig.apiKey == nil {
                log.notice("RevenueCat not configured (no REVENUECAT_API_KEY) — purchases disabled.")
            }
            return
        }
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(with: Configuration.Builder(withAPIKey: key).build())
        isConfigured = true

        // Follow Firebase auth so RevenueCat's appUserID == the Firebase uid. The listener fires
        // immediately with the current user and again when anonymous sign-in restores/creates one.
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let uid = user?.uid else { return }
            Task { await self?.identify(uid) }
        }
        // Live entitlement updates (purchase, renewal, expiry, cross-device, sandbox changes).
        infoTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
        Task { await refreshOfferings() }
    }

    private func identify(_ uid: String) async {
        guard isConfigured, Purchases.shared.appUserID != uid else { return }
        do {
            let (info, _) = try await Purchases.shared.logIn(uid)
            apply(info)
            await refreshFreeScans()
            log.debug("RevenueCat identified as Firebase uid")
        } catch {
            log.error("RevenueCat logIn failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reads

    /// Fetch the offering whose packages the paywall renders.
    func refreshOfferings() async {
        guard isConfigured else { return }
        do {
            let offerings = try await Purchases.shared.offerings()
            offering = offerings.offering(identifier: Self.offeringID) ?? offerings.current
        } catch {
            log.error("RevenueCat offerings failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Read the server-owned quota doc for the "N free scans left" display. Best-effort + read-only
    /// (the client can't write it; the backend owns it). Skipped once subscribed.
    func refreshFreeScans() async {
        guard !isSubscribed, let uid = Auth.auth().currentUser?.uid else { return }
        let snap = try? await Firestore.firestore()
            .collection("users").document(uid)
            .collection("quota").document("summary").getDocument()
        let used = (snap?.data()?["lifetimeFreeUsed"] as? NSNumber)?.intValue ?? 0
        remainingFreeScans = max(Self.freeLifetimeLimit - used, 0)
    }

    /// Server-authoritative free-scan count straight from the latest `scanMeal` response. `nil`
    /// when the user isn't on the free tier (paid → unlimited within the monthly cap).
    func noteRemainingFreeScans(_ remaining: Int?) {
        remainingFreeScans = remaining
    }

    // MARK: - Actions

    @discardableResult
    func purchase(_ package: Package) async -> PurchaseOutcome {
        guard isConfigured else { return .failed }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            apply(result.customerInfo)
            return isSubscribed ? .subscribed : .failed
        } catch {
            log.error("RevenueCat purchase failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    @discardableResult
    func restore() async -> PurchaseOutcome {
        guard isConfigured else { return .failed }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            return isSubscribed ? .subscribed : .cancelled   // .cancelled == "nothing to restore"
        } catch {
            log.error("RevenueCat restore failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// Apple's native "manage subscriptions" sheet — the required path to cancel / change plan
    /// (we don't ship RevenueCat's Customer Center; this covers the requirement).
    func manageSubscriptions() async {
        guard isConfigured else { return }
        do {
            try await Purchases.shared.showManageSubscriptions()
        } catch {
            log.error("showManageSubscriptions failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ info: CustomerInfo) {
        isSubscribed = info.entitlements.active[Self.entitlementID]?.isActive == true
    }
}
