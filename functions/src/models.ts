import { Timestamp } from 'firebase-admin/firestore';

export type PlanTier = 'free' | 'premiumMonthly' | 'premiumYearly' | 'power';

export type ScanType = 'meal_photo' | 'nutrition_label' | 'packaged_food';

export type ScanLifecycleState =
  | 'created'
  | 'reserved'
  | 'upload_url_issued'
  | 'uploaded'
  | 'processing'
  | 'completed'
  | 'failed'
  | 'refunded'
  | 'expired'
  | 'deleted';

export type ScanOutcome = 'success' | 'failure';

export interface PlanTiersConfig {
  free: {
    monthlyScans: number;
    dailyScans: number;
  };
  premiumMonthly: {
    monthlyScans: number;
    dailyScans: number;
  };
  premiumYearly: {
    monthlyScans: number;
    dailyScans: number;
  };
  power: {
    monthlyScans: number;
    dailyScans: number;
  };
}

export interface PlanState {
  uid: string;
  tier: PlanTier;
  source: 'revenuecat' | 'bootstrap';
  hasActiveEntitlement: boolean;
  updatedAt: Timestamp;
  graceUntil?: Timestamp;
}

export interface DailyQuotaWindow {
  date: string;
  used: number;
  reserved: number;
  failed: number;
}

export interface ScanQuotaSummary {
  uid: string;
  tier: PlanTier;
  monthlyLimit: number;
  monthlyUsed: number;
  monthlyReserved: number;
  dailyLimit: number;
  dailyWindows: Record<string, DailyQuotaWindow>;
  updatedAt: Timestamp;
}

export interface QuotaReserveResult {
  canReserve: boolean;
  reason?: QuotaRejectReason;
  remainingMonthly: number;
  remainingDaily: number;
}

export type QuotaRejectReason =
  | 'MISSING_ENTITLEMENT'
  | 'OVER_DAILY_LIMIT'
  | 'OVER_MONTHLY_LIMIT'
  | 'PLAN_NOT_FOUND'
  | 'SCAN_IN_PROGRESS';

export interface ScanLifecycleEvent {
  state: ScanLifecycleState;
  actor: 'backend' | 'scan_worker';
  reason?: string;
  createdAt: Timestamp;
}

export interface ScanModelSelection {
  provider: 'gemini' | 'claude' | 'other';
  model: string;
  routedBy: {
    tier: PlanTier;
    scanType: ScanType;
  };
  temperature?: number;
  maxOutputTokens?: number;
}

export interface ScanResultPayload {
  scanId: string;
  uid: string;
  scanType: ScanType;
  status: ScanLifecycleState;
  outcome: ScanOutcome;
  title: string;
  totalKcal?: number;
  confidence: number;
  notes?: string;
  nutrients: Array<{
    name: string;
    quantity: number;
    unit: string;
    dailyTargetPercent?: number;
  }>;
  recipeSuggestions?: string[];
  detectedFoods?: string[];
  model: ScanModelSelection;
  completedAt: Timestamp;
}

export interface R2ObjectMetadata {
  scanId: string;
  uid: string;
  bucket: string;
  key: string;
  contentType: string;
  sha256?: string;
  sizeBytes: number;
  retentionClass: 'retain' | 'delete_after_success';
  createdAt: Timestamp;
  updatedAt: Timestamp;
  expiresAt?: Timestamp;
  uploadedBy: 'app' | 'backend';
}

export type RevenueCatWebhookEventType =
  | 'INITIAL_PURCHASE'
  | 'RENEWAL'
  | 'CANCELLATION'
  | 'UNCANCELLATION'
  | 'EXPIRATION'
  | 'BILLING_ISSUE'
  | 'TEST'
  | 'UNKNOWN';

export interface RevenueCatEnvironment {
  id?: string;
  project_id?: string;
  app_id?: string;
}

export interface RevenueCatWebhookEvent {
  id: string;
  event_type: string;
  event_ts?: number;
  alias?: string;
  event?: RevenueCatWebhookEventType;
  event_name?: string;
  app_id?: string;
  webhook_id?: string;
  api_version?: string;
  environment?: RevenueCatEnvironment;
  event_data?: RevenueCatEventData;
  subscriber?: RevenueCatEventSubscriberDetails;
  created_at?: number;
}

export interface RevenueCatEventData {
  app_user_id?: string;
  original_app_user_id?: string;
  product_id?: string;
  base_plan_id?: string;
  entitlement_id?: string;
  entitlement_ids?: string[];
  period_type?: string;
  purchased_at_ms?: number;
  grace_period_expires_at_ms?: number;
}

export interface RevenueCatEventSubscriberDetails {
  app_user_id?: string;
  original_app_user_id?: string;
  first_seen?: number;
  custom_data?: Record<string, unknown>;
  non_subscriptions?: unknown[];
  presented_offerings?: unknown[];
  subscriptions?: Record<string, unknown>;
  entitlements?: Record<string, unknown>;
}

export interface ScanReservation {
  uid: string;
  scanId: string;
  scanType: ScanType;
  planTierAtReserve: PlanTier;
  quotaReservedAt: Timestamp;
  quotaReservedBy: 'backend';
  status: ScanLifecycleState;
  lifecycle: ScanLifecycleEvent[];
  r2: R2ObjectMetadata;
  model?: ScanModelSelection;
  result?: ScanResultPayload;
  createdAt?: Timestamp;
  updatedAt?: Timestamp;
  finalizedAt?: Timestamp;
  refundedAt?: Timestamp | string;
  lastHeartbeat?: Timestamp;
  quota?: {
    monthKey: string;
    note: string;
    summary: ScanQuotaSummary;
    model: ScanModelSelection;
  };
}
