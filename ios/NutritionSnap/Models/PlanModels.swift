import Foundation

// MARK: - Plan and status model

/// Entitlement tiers used by both current PRD scope and future expansion.
enum PlanTier: String, Codable, Hashable, CaseIterable {
    case free
    case premiumMonthly
    case premiumYearly
    case power

    /// Useful for forward-compatible decoding of older or unknown plan values.
    case unknown

    var isFree: Bool {
        self == .free
    }

    var isPremium: Bool {
        self == .premiumMonthly || self == .premiumYearly
    }

    var isPower: Bool {
        self == .power
    }

    var displayName: String {
        switch self {
        case .free:          return "Free"
        case .premiumMonthly: return "Premium (monthly)"
        case .premiumYearly:  return "Premium (yearly)"
        case .power:         return "Power"
        case .unknown:       return "Unknown"
        }
    }
}

/// Billing/state status for a user plan. Backend is the source of truth later.
///
/// Includes v1 plus future PRD states (`Billing issue`, `Cancelled but active`, etc.)
/// so the client can surface stable behavior without redeploying for every backend state.
enum PlanStatus: String, Codable, Hashable {
    case noEntitlement
    case active
    case billingIssue
    case cancelledButActive
    case expired
    case refunded
    case productChanged
    case gracePeriod
    case suspended
    case unknown

    var allowsScanning: Bool {
        self == .active || self == .gracePeriod
    }

    var requiresReauthOrRestore: Bool {
        switch self {
        case .noEntitlement, .billingIssue, .expired, .refunded, .productChanged, .suspended:
            true
        default:
            false
        }
    }
}

// MARK: - Scan domain

/// Scan types the backend and client use consistently.
enum ScanType: String, Codable, Hashable, CaseIterable {
    case mealPhoto = "meal_photo"
    case nutritionLabel = "nutrition_label"
    case packagedFood = "packaged_food"
}

/// Scan lifecycle statuses that can be surfaced locally while reservation flow is mocked.
enum ScanReservationStatus: String, Codable, Hashable {
    case created
    case reserved
    case uploadUrlIssued
    case uploaded
    case processing
    case completed
    case failed
    case refunded
    case expired
    case deleted

    var isTerminal: Bool {
        switch self {
        case .completed, .refunded, .expired, .deleted, .failed:
            return true
        case .created, .reserved, .uploadUrlIssued, .uploaded, .processing:
            return false
        }
    }
}

/// Client-visible reason for a quota/feature gate rejection.
enum QuotaRejectionReason: String, Codable, Hashable {
    case planMissing
    case planInactive
    case monthlyQuotaReached
    case dailyQuotaReached
    case enhancedScanningUnavailable
    case imageHistoryUnavailable
    case reservationFailed
    case unknown
}

extension QuotaRejectionReason: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .planMissing: return "No active plan is linked to this account."
        case .planInactive: return "Your plan is currently inactive."
        case .monthlyQuotaReached: return "You reached this month's scan limit."
        case .dailyQuotaReached: return "You reached today's scan limit."
        case .enhancedScanningUnavailable: return "Enhanced scanning isn't available on this plan."
        case .imageHistoryUnavailable: return "Image history isn't available on this plan."
        case .reservationFailed: return "A scan reservation could not be created."
        case .unknown: return "The scan could not be started."
        }
    }
}

struct ScanStartDecision: Hashable {
    let canStart: Bool
    let rejectionReason: QuotaRejectionReason?
    let summary: PlanSummary

    static func canStart(from summary: PlanSummary) -> ScanStartDecision {
        ScanStartDecision(canStart: true, rejectionReason: nil, summary: summary)
    }

    static func rejected(_ reason: QuotaRejectionReason, from summary: PlanSummary) -> ScanStartDecision {
        ScanStartDecision(canStart: false, rejectionReason: reason, summary: summary)
    }
}

// MARK: - Feature flags + quotas

/// PRD-aligned feature switches used by the client to conditionally expose UI.
struct PlanFeatureFlags: Codable, Hashable {
    /// Whether raw scan images can be retained and shown as history/reprocessing source.
    var imageHistory: Bool

    /// Whether the better/fallback scan path is allowed.
    var enhancedScanning: Bool

    /// Power-tier marker kept in case the server enables it later.
    var priorityProcessing: Bool

    static let free = PlanFeatureFlags(imageHistory: false, enhancedScanning: false, priorityProcessing: false)
    static let premiumMonthly = PlanFeatureFlags(imageHistory: true, enhancedScanning: true, priorityProcessing: false)
    static let premiumYearly = PlanFeatureFlags(imageHistory: true, enhancedScanning: true, priorityProcessing: false)
    static let power = PlanFeatureFlags(imageHistory: true, enhancedScanning: true, priorityProcessing: true)
    static let unknown = PlanFeatureFlags(imageHistory: false, enhancedScanning: false, priorityProcessing: false)
}

/// Per-window quota counters shown to the user.
struct QuotaSummary: Codable, Hashable {
    /// Daily limit (caps burst usage).
    var dailyLimit: Int
    /// Monthly limit (keeps total cost controlled).
    var monthlyLimit: Int

    /// Successful scans this window.
    var monthlyUsed: Int
    var monthlyReserved: Int

    /// Successful scans this day window.
    var dailyUsed: Int
    var dailyReserved: Int

    /// Window anchors; used for local roll-over while no backend is available.
    var dailyWindowStart: Date
    var monthlyWindowStart: Date

    var dailyRemaining: Int {
        max(0, dailyLimit - (dailyUsed + dailyReserved))
    }

    var monthlyRemaining: Int {
        max(0, monthlyLimit - (monthlyUsed + monthlyReserved))
    }

    var hasDailyHeadroom: Bool { dailyRemaining > 0 }
    var hasMonthlyHeadroom: Bool { monthlyRemaining > 0 }

    /// Local check used by the in-memory service before reservation.
    var rejectionReasonForNewReservation: QuotaRejectionReason? {
        if !hasMonthlyHeadroom { return .monthlyQuotaReached }
        if !hasDailyHeadroom { return .dailyQuotaReached }
        return nil
    }

    mutating func reserveOneScan() {
        monthlyReserved += 1
        dailyReserved += 1
    }

    mutating func finalizeOneScan() {
        monthlyReserved = max(0, monthlyReserved - 1)
        dailyReserved = max(0, dailyReserved - 1)
        monthlyUsed += 1
        dailyUsed += 1
    }

    mutating func refundOneScan() {
        monthlyReserved = max(0, monthlyReserved - 1)
        dailyReserved = max(0, dailyReserved - 1)
    }

    mutating func resetDaily(to start: Date) {
        dailyWindowStart = start
        dailyUsed = 0
        dailyReserved = 0
    }

    mutating func resetMonthly(to start: Date) {
        monthlyWindowStart = start
        monthlyUsed = 0
        monthlyReserved = 0
    }
}

// MARK: - Plan + reservation summary

struct PlanSummary: Codable, Hashable {
    var tier: PlanTier
    var status: PlanStatus
    var featureFlags: PlanFeatureFlags
    var quota: QuotaSummary

    var userId: String?
    var currentPeriodEnd: Date?
    var graceUntil: Date?

    var isScanningAllowed: Bool { status.allowsScanning }
    var canUseEnhancedScanning: Bool { featureFlags.enhancedScanning }
    var canUseImageHistory: Bool { featureFlags.imageHistory }
}

struct ScanReservationSummary: Codable, Hashable {
    let id: String
    let scanType: ScanType
    let planTier: PlanTier
    let requestedAt: Date
    let expiresAt: Date
    let requiresEnhanced: Bool
    let requiresImageHistory: Bool
    let status: ScanReservationStatus

    var isActive: Bool { !status.isTerminal }
}
