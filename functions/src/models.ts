import { Timestamp } from 'firebase-admin/firestore';

export type PlanTier = 'free' | 'premiumMonthly' | 'premiumYearly' | 'power';

export type ScanType = 'meal_photo' | 'nutrition_label' | 'packaged_food';

/** Entitlement state at users/{uid}/plan/current — written ONLY by the RevenueCat webhook. */
export interface PlanState {
  uid: string;
  tier: PlanTier;
  source: 'revenuecat' | 'bootstrap';
  hasActiveEntitlement: boolean;
  updatedAt: Timestamp;
}

export interface MonthlyUsage {
  used: number;
  reserved: number;
}

/**
 * Backend-owned usage ledger at users/{uid}/quota/summary. The client may READ it (rules) to
 * show remaining scans, but never writes it — the whole trust boundary depends on that.
 */
export interface QuotaDoc {
  uid: string;
  /** Free tier: a small lifetime allowance (the "taste"). */
  lifetimeFreeUsed: number;
  lifetimeFreeReserved: number;
  /** Paid tiers: usage per calendar month (yyyy-MM), reset implicitly by keying on the month. */
  months: Record<string, MonthlyUsage>;
  updatedAt: Timestamp;
}

export type QuotaRejectReason =
  | 'MISSING_ENTITLEMENT'
  | 'OVER_FREE_LIMIT'
  | 'OVER_MONTHLY_LIMIT';

export type ScanStatus = 'completed' | 'failed' | 'not_food';

/** Minimal audit record at users/{uid}/scans/{scanId}; backend-owned (rules: client read-only). */
export interface ScanRecord {
  uid: string;
  scanId: string;
  scanType: ScanType;
  tier: PlanTier;
  status: ScanStatus;
  model: string;
  createdAt: Timestamp;
  itemCount: number;
  kcal: number;
  confidence: number;
}

/**
 * The wire contract Gemini returns (PRD §6) — mirrors the Swift `EstimatedMeal`. The backend
 * validates this shape and passes it back to the client unchanged, so both share one decoder.
 */
export interface EstimatedMealWire {
  items: Array<{
    name: string;
    portion: string;
    kcal: number;
    protein: number;
    carbs: number;
    fat: number;
    confidence: number;
  }>;
  totals?: { kcal: number; protein: number; carbs: number; fat: number };
  micros?: Record<string, number>;
  balanceNote: string;
  source: 'vision' | 'ocr';
  notFood?: boolean;
}

// MARK: - RevenueCat webhook

export type RevenueCatEventType =
  | 'INITIAL_PURCHASE'
  | 'RENEWAL'
  | 'CANCELLATION'
  | 'UNCANCELLATION'
  | 'EXPIRATION'
  | 'BILLING_ISSUE'
  | 'PRODUCT_CHANGE'
  | 'SUBSCRIPTION_PAUSED'
  | 'TEST'
  | 'UNKNOWN';

/** The real RevenueCat v1 webhook nests everything under `event`. */
export interface RevenueCatEvent {
  id?: string;
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  product_id?: string;
  entitlement_ids?: string[];
  period_type?: string;
  expiration_at_ms?: number;
  purchased_at_ms?: number;
  grace_period_expires_at_ms?: number;
}

export interface RevenueCatWebhookBody {
  api_version?: string;
  event?: RevenueCatEvent;
}
