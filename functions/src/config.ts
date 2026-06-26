export const FUNCTIONS_REGION = 'us-central1';

export const firestoreCollections = {
  users: 'users',
  scans: 'scans',
  webhooks: 'webhooks',
  revenuecat: 'revenuecat',
} as const;

export const functionConfig = {
  // Free tier is a small LIFETIME taste (grill 2026-06-26), not a recurring quota — it bounds
  // free Gemini spend. A reinstall resets it (anonymous uid); acceptable for v1, harden with
  // DeviceCheck later if abused.
  freeLifetimeLimit: Number(process.env.FREE_LIFETIME_SCAN_LIMIT ?? '3'),
  // Paid tiers: a generous monthly ceiling (PRD: "prefer quotas over unlimited") that caps LLM
  // cost without feeling like a limit at ~100–150 scans/user/month.
  premiumMonthlyLimit: Number(process.env.PREMIUM_MONTHLY_SCAN_LIMIT ?? '300'),
  premiumYearlyMonthlyLimit: Number(process.env.PREMIUM_YEARLY_MONTHLY_SCAN_LIMIT ?? '300'),
  powerMonthlyLimit: Number(process.env.POWER_MONTHLY_SCAN_LIMIT ?? '1000'),
  // Inline image cap. A downsampled ≤1600px JPEG is well under this; reject larger to bound
  // request size, cost, and latency.
  maxImageMb: Number(process.env.MAX_IMAGE_MB ?? '8'),
  geminiModel: process.env.GEMINI_MODEL ?? 'gemini-2.5-flash',
} as const;
