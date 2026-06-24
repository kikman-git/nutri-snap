import Foundation
import Observation

enum PlanServiceError: Error, LocalizedError {
    case scanRejected(QuotaRejectionReason?)

    var errorDescription: String? {
        switch self {
        case .scanRejected(let reason):
            return reason?.errorDescription ?? "The scan could not be started."
        }
    }
}

@MainActor
protocol PlanService: AnyObject {
    var currentPlan: PlanSummary { get }

    /// Recompute any local window/timeout state and return the active plan summary.
    func refreshPlanSummary() async -> PlanSummary

    /// Baseline check before upload/requesting a reservation.
    func canStartScan() async -> ScanStartDecision

    /// Baseline check with feature intent.
    func canStartScan(scanType: ScanType,
                      requiresImageHistory: Bool,
                      requiresEnhancedScanning: Bool) async -> ScanStartDecision

    /// Reserve one scan credit locally. Backend replacement will perform the real reservation.
    func startScanReservation(scanType: ScanType,
                             requiresImageHistory: Bool,
                             requiresEnhancedScanning: Bool) async throws -> ScanReservationSummary

    /// Mark an in-flight reservation as complete (a successful scan).
    func finalizeReservation(_ reservation: ScanReservationSummary) async

    /// Return a reservation credit if the scan fails or is abandoned.
    func refundReservation(_ reservation: ScanReservationSummary, reason: QuotaRejectionReason?) async
}

extension PlanService {
    func canStartScan() async -> ScanStartDecision {
        await canStartScan(scanType: .mealPhoto, requiresImageHistory: false, requiresEnhancedScanning: false)
    }

    func startScanReservation(scanType: ScanType) async throws -> ScanReservationSummary {
        try await startScanReservation(scanType: scanType,
                                      requiresImageHistory: false,
                                      requiresEnhancedScanning: false)
    }
}

/// Local in-memory implementation used for previews/dev until backend functions are ready.
///
/// Behavior is simple and deterministic: every successful `startScanReservation` increments
/// a local reserved counter; successful completion decrements reserved and increments used.
@MainActor
@Observable
final class InMemoryPlanService: PlanService {
    private enum Constants {
        static let reservationTTL: TimeInterval = 10 * 60

        static let free = PlanQuotaPolicy(
            tier: .free,
            dailyLimit: 6,
            monthlyLimit: 40,
            featureFlags: .free)

        static let premiumMonthly = PlanQuotaPolicy(
            tier: .premiumMonthly,
            dailyLimit: 30,
            monthlyLimit: 600,
            featureFlags: .premiumMonthly)

        static let premiumYearly = PlanQuotaPolicy(
            tier: .premiumYearly,
            dailyLimit: 40,
            monthlyLimit: 1000,
            featureFlags: .premiumYearly)

        static let power = PlanQuotaPolicy(
            tier: .power,
            dailyLimit: 80,
            monthlyLimit: 1800,
            featureFlags: .power)
    }

    private struct PlanQuotaPolicy {
        let tier: PlanTier
        let dailyLimit: Int
        let monthlyLimit: Int
        let featureFlags: PlanFeatureFlags
    }

    private(set) var currentPlan: PlanSummary
    private var reservations: [String: ScanReservationSummary] = [:]
    private let now: () -> Date

    init(tier: PlanTier = .free,
         status: PlanStatus = .active,
         now: @escaping () -> Date = Date.init,
         userId: String? = nil) {
        self.now = now

        let policy = Self.policy(for: tier)
        let current = now()
        let quota = QuotaSummary(
            dailyLimit: policy.dailyLimit,
            monthlyLimit: policy.monthlyLimit,
            monthlyUsed: 0,
            monthlyReserved: 0,
            dailyUsed: 0,
            dailyReserved: 0,
            dailyWindowStart: Self.startOfDay(current),
            monthlyWindowStart: Self.startOfMonth(current))

        currentPlan = PlanSummary(
            tier: tier,
            status: status,
            featureFlags: policy.featureFlags,
            quota: quota,
            userId: userId,
            currentPeriodEnd: nil,
            graceUntil: nil)
    }

    func refreshPlanSummary() async -> PlanSummary {
        reconcileWindowAndReservations(now: now())
        return currentPlan
    }

    func canStartScan(scanType: ScanType,
                      requiresImageHistory: Bool,
                      requiresEnhancedScanning: Bool) async -> ScanStartDecision {
        reconcileWindowAndReservations(now: now())

        if !currentPlan.isScanningAllowed {
            let reason: QuotaRejectionReason = currentPlan.status == .noEntitlement
            ? .planMissing : .planInactive
            return .rejected(reason, from: currentPlan)
        }

        if requiresEnhancedScanning && !currentPlan.featureFlags.enhancedScanning {
            return .rejected(.enhancedScanningUnavailable, from: currentPlan)
        }

        if requiresImageHistory && !currentPlan.featureFlags.imageHistory {
            return .rejected(.imageHistoryUnavailable, from: currentPlan)
        }

        if let reason = currentPlan.quota.rejectionReasonForNewReservation {
            return .rejected(reason, from: currentPlan)
        }

        return .canStart(from: currentPlan)
    }

    func startScanReservation(scanType: ScanType,
                              requiresImageHistory: Bool,
                              requiresEnhancedScanning: Bool) async throws -> ScanReservationSummary {
        let decision = await canStartScan(scanType: scanType,
                                          requiresImageHistory: requiresImageHistory,
                                          requiresEnhancedScanning: requiresEnhancedScanning)
        guard decision.canStart else {
            throw PlanServiceError.scanRejected(decision.rejectionReason)
        }

        reconcileWindowAndReservations(now: now())
        let id = UUID().uuidString
        let startedAt = now()
        let reservation = ScanReservationSummary(
            id: id,
            scanType: scanType,
            planTier: currentPlan.tier,
            requestedAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(Constants.reservationTTL),
            requiresEnhanced: requiresEnhancedScanning,
            requiresImageHistory: requiresImageHistory,
            status: .reserved)

        currentPlan.quota.reserveOneScan()
        reservations[id] = reservation
        return reservation
    }

    func finalizeReservation(_ reservation: ScanReservationSummary) async {
        reconcileWindowAndReservations(now: now())

        guard var active = reservations[reservation.id] else { return }
        guard active.status == .reserved || active.status == .processing || active.status == .uploaded else { return }
        active = ScanReservationSummary(
            id: active.id,
            scanType: active.scanType,
            planTier: active.planTier,
            requestedAt: active.requestedAt,
            expiresAt: active.expiresAt,
            requiresEnhanced: active.requiresEnhanced,
            requiresImageHistory: active.requiresImageHistory,
            status: .completed)

        reservations[active.id] = active
        currentPlan.quota.finalizeOneScan()
    }

    func refundReservation(_ reservation: ScanReservationSummary, reason: QuotaRejectionReason?) async {
        _ = reason
        reconcileWindowAndReservations(now: now())

        guard var active = reservations[reservation.id] else { return }
        guard !active.status.isTerminal else { return }

        active = ScanReservationSummary(
            id: active.id,
            scanType: active.scanType,
            planTier: active.planTier,
            requestedAt: active.requestedAt,
            expiresAt: active.expiresAt,
            requiresEnhanced: active.requiresEnhanced,
            requiresImageHistory: active.requiresImageHistory,
            status: .refunded)

        reservations[active.id] = active
        currentPlan.quota.refundOneScan()
    }

    // MARK: - Internal helpers

    private static func policy(for tier: PlanTier) -> PlanQuotaPolicy {
        switch tier {
        case .free: return Constants.free
        case .premiumMonthly: return Constants.premiumMonthly
        case .premiumYearly: return Constants.premiumYearly
        case .power: return Constants.power
        case .unknown: return Constants.free
        }
    }

    private func reconcileWindowAndReservations(now nowDate: Date) {
        let today = Self.startOfDay(nowDate)
        let month = Self.startOfMonth(nowDate)
        let windowRolled = currentPlan.quota.dailyWindowStart < today
                        || currentPlan.quota.monthlyWindowStart < month

        if windowRolled {
            purgeReservations { _ in true }
        }

        if currentPlan.quota.dailyWindowStart < today {
            currentPlan.quota.resetDaily(to: today)
        }

        if currentPlan.quota.monthlyWindowStart < month {
            currentPlan.quota.resetMonthly(to: month)
        }

        if currentPlan.status == .gracePeriod,
           let graceUntil = currentPlan.graceUntil,
           graceUntil < nowDate {
            currentPlan.status = .active
        }

        purgeReservations { $0.expiresAt <= nowDate }
    }

    private func purgeReservations(where shouldPurge: (ScanReservationSummary) -> Bool) {
        let idsToPurge = reservations.values.filter(shouldPurge).map(\.id)
        for id in idsToPurge {
            guard let reservation = reservations.removeValue(forKey: id) else { continue }
            if reservation.status != .completed {
                currentPlan.quota.refundOneScan()
            }
        }
    }

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: components) ?? startOfDay(date)
    }
}
