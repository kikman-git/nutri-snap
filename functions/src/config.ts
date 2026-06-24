export const FUNCTIONS_REGION = 'us-central1';

export const firestoreCollections = {
  users: 'users',
  scans: 'scans',
  webhooks: 'webhooks',
  revenuecat: 'revenuecat'
} as const;

export const functionConfig = {
  freeMonthlyLimit: Number(process.env.FREE_MONTHLY_SCAN_LIMIT ?? '20'),
  freeDailyLimit: Number(process.env.FREE_DAILY_SCAN_LIMIT ?? '3'),
  premiumMonthlyLimit: Number(process.env.PREMIUM_MONTHLY_SCAN_LIMIT ?? '300'),
  premiumDailyLimit: Number(process.env.PREMIUM_DAILY_SCAN_LIMIT ?? '30'),
  premiumYearlyMonthlyLimit: Number(process.env.PREMIUM_YEARLY_MONTHLY_SCAN_LIMIT ?? '1000'),
  premiumYearlyDailyLimit: Number(process.env.PREMIUM_YEARLY_DAILY_SCAN_LIMIT ?? '40'),
  powerMonthlyLimit: Number(process.env.POWER_MONTHLY_SCAN_LIMIT ?? '1800'),
  powerDailyLimit: Number(process.env.POWER_DAILY_SCAN_LIMIT ?? '80'),
  maxUploadSizeMb: Number(process.env.MAX_R2_UPLOAD_MB ?? '25'),
  scanResultTimeoutMinutes: Number(process.env.SCAN_RESULT_TIMEOUT_MINUTES ?? '30'),
  r2Bucket: process.env.R2_BUCKET_NAME || 'nutrition-snap-scans',
  r2AccountId: process.env.R2_ACCOUNT_ID || 'TODO_ACCOUNT_ID',
  r2Endpoint: process.env.R2_ENDPOINT || 'https://<ACCOUNT_ID>.r2.cloudflarestorage.com'
} as const;

export const envSecretKeys = {
  appCheckEnabled: process.env.APP_CHECK_REQUIRED === 'true',
  revenueCatWebhookSecret: process.env.REVENUECAT_WEBHOOK_SHARED_SECRET || ''
};
