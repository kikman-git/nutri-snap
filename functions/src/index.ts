import {
  HttpsError,
  onCall,
  onRequest,
} from 'firebase-functions/v2/https';
import { Timestamp, DocumentReference, DocumentSnapshot } from 'firebase-admin/firestore';
import { initializeApp, getApps, getApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

import {
  DailyQuotaWindow,
  PlanState,
  PlanTier,
  PlanTiersConfig,
  QuotaReserveResult,
  R2ObjectMetadata,
  RevenueCatWebhookEvent,
  ScanLifecycleEvent,
  ScanLifecycleState,
  ScanModelSelection,
  ScanQuotaSummary,
  ScanResultPayload,
  ScanType,
  ScanReservation,
} from './models';
import { envSecretKeys, functionConfig, firestoreCollections, FUNCTIONS_REGION } from './config';

const app = getApps().length ? getApp() : initializeApp();
const db = getFirestore(app);

if (!db) {
  throw new Error('Firestore initialization failed');
}

const PLAN_TIER_DEFAULTS: PlanTiersConfig = {
  free: {
    monthlyScans: functionConfig.freeMonthlyLimit,
    dailyScans: functionConfig.freeDailyLimit,
  },
  premiumMonthly: {
    monthlyScans: functionConfig.premiumMonthlyLimit,
    dailyScans: functionConfig.premiumDailyLimit,
  },
  premiumYearly: {
    monthlyScans: functionConfig.premiumYearlyMonthlyLimit,
    dailyScans: functionConfig.premiumYearlyDailyLimit,
  },
  power: {
    monthlyScans: functionConfig.powerMonthlyLimit,
    dailyScans: functionConfig.powerDailyLimit,
  },
};

function now(): Timestamp {
  return Timestamp.now();
}

function todayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function monthKey(date: Date): string {
  return date.toISOString().slice(0, 7);
}

function resolvePlanTier(value: unknown): PlanTier {
  switch (value) {
    case 'premiumMonthly':
    case 'premiumYearly':
    case 'power':
      return value;
    // Backward-compatible with the first scaffold and any coarse RevenueCat mapping.
    case 'premium':
      return 'premiumMonthly';
    default:
      return 'free';
  }
}

function isPaidTier(tier: PlanTier): boolean {
  return tier !== 'free';
}

function toPlanState(uid: string, data: Record<string, unknown>): PlanState {
  const tier = resolvePlanTier(data.tier);
  return {
    uid,
    tier,
    source: (data.source as PlanState['source']) ?? 'bootstrap',
    hasActiveEntitlement: Boolean(data.hasActiveEntitlement),
    updatedAt: data.updatedAt instanceof Timestamp
      ? data.updatedAt
      : now(),
    graceUntil: data.graceUntil instanceof Timestamp ? data.graceUntil : undefined,
  };
}

function defaultQuotaSummary(uid: string, tier: PlanTier): ScanQuotaSummary {
  const planConfig = PLAN_TIER_DEFAULTS[tier];
  return {
    uid,
    tier,
    monthlyLimit: planConfig.monthlyScans,
    monthlyUsed: 0,
    monthlyReserved: 0,
    dailyLimit: planConfig.dailyScans,
    dailyWindows: {},
    updatedAt: now(),
  };
}

function getQuotaSummaryFromDoc(snapshot: DocumentSnapshot): ScanQuotaSummary {
  const data = (snapshot.data() ?? {}) as Record<string, unknown>;
  const tier = resolvePlanTier(data.tier);
  const dailyWindows = (data.dailyWindows as Record<string, DailyQuotaWindow>) ?? {};

  return {
    uid: (data.uid as string) ?? snapshot.ref.parent.parent?.id ?? 'unknown',
    tier,
    monthlyLimit: (data.monthlyLimit as number) ?? PLAN_TIER_DEFAULTS[tier].monthlyScans,
    monthlyUsed: (data.monthlyUsed as number) ?? 0,
    monthlyReserved: (data.monthlyReserved as number) ?? 0,
    dailyLimit: (data.dailyLimit as number) ?? PLAN_TIER_DEFAULTS[tier].dailyScans,
    dailyWindows,
    updatedAt: data.updatedAt instanceof Timestamp ? data.updatedAt : now(),
  };
}

function quotaCanReserve(summary: ScanQuotaSummary): QuotaReserveResult {
  const currentDate = todayKey(new Date());
  const daily = summary.dailyWindows[currentDate] ?? {
    date: currentDate,
    used: 0,
    reserved: 0,
    failed: 0,
  };

  const monthlyRemaining = summary.monthlyLimit - summary.monthlyUsed - summary.monthlyReserved;
  if (monthlyRemaining <= 0) {
    return {
      canReserve: false,
      reason: 'OVER_MONTHLY_LIMIT',
      remainingMonthly: 0,
      remainingDaily: Math.max(summary.dailyLimit - daily.used - daily.reserved, 0),
    };
  }

  const dailyRemaining = summary.dailyLimit - daily.used - daily.reserved;
  if (dailyRemaining <= 0) {
    return {
      canReserve: false,
      reason: 'OVER_DAILY_LIMIT',
      remainingMonthly: Math.max(monthlyRemaining, 0),
      remainingDaily: 0,
    };
  }

  return {
    canReserve: true,
    remainingMonthly: monthlyRemaining,
    remainingDaily: dailyRemaining,
  };
}

function resolveScanType(value: unknown): ScanType {
  const allowed: ScanType[] = ['meal_photo', 'nutrition_label', 'packaged_food'];
  if (typeof value === 'string' && allowed.includes(value as ScanType)) {
    return value as ScanType;
  }
  throw new HttpsError('invalid-argument', 'scanType must be meal_photo, nutrition_label, or packaged_food');
}

function assertAuthenticated(context: { auth?: { uid?: string } }): string {
  if (!context.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required for scan operations.');
  }
  return context.auth.uid;
}

function assertAppCheck(context: { app?: { appId?: string } }): void {
  // TODO boundary: backend requires App Check for scan-related callables in production.
  if (!envSecretKeys.appCheckEnabled) {
    return;
  }
  if (!context.app?.appId) {
    throw new HttpsError('failed-precondition', 'App Check token required for this endpoint.');
  }
}

function scanUploadKey(uid: string, scanType: ScanType, scanId: string, contentType: string): string {
  const safeScanType = scanType.replace(/[^a-z_]/g, '');
  const extension = contentType.toLowerCase().includes('png')
    ? 'png'
    : contentType.toLowerCase().includes('webp')
      ? 'webp'
      : 'jpg';
  return `${uid}/${safeScanType}/${scanId}.${extension}`;
}

function fakeSignedUploadUrl(
  r2Key: string,
  contentType: string,
): {
  url: string;
  method: 'PUT';
  expiresAt: Timestamp;
  headers: Record<string, string>;
} {
  return {
    // TODO boundary: real Cloudflare R2 signed URL generation must be implemented server-side here.
    url: `${functionConfig.r2Endpoint.replace(/\/$/, '')}/${encodeURIComponent(r2Key)}?placeholder-signed-url=true`,
    method: 'PUT',
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 15 * 60 * 1000)),
    headers: {
      'content-type': contentType,
      'x-amz-checksum-sha256': 'TODO_SERVER_GENERATED_FOR_REAL_SIGNING',
    },
  };
}

function buildLifecycleTransition(
  state: ScanLifecycleState,
  actor: ScanLifecycleEvent['actor'],
  reason?: string,
): ScanLifecycleEvent {
  return { state, actor, reason, createdAt: now() };
}

function nextModelSelection(tier: PlanTier, scanType: ScanType): ScanModelSelection {
  // TODO boundary: backend owns model policy and may swap provider by tier/scanType over time.
  return isPaidTier(tier)
    ? {
      provider: 'gemini',
      model: 'gemini-2.5-flash',
      routedBy: { tier, scanType },
      temperature: 0.1,
    }
    : {
      provider: 'gemini',
      model: 'gemini-2.5-flash',
      routedBy: { tier, scanType },
      temperature: 0.0,
    };
}

function makePlaceholderResult(scanId: string, uid: string, scanType: ScanType, tier: PlanTier): ScanResultPayload {
  return {
    scanId,
    uid,
    scanType,
    status: 'completed',
    outcome: 'success',
    title: `Placeholder result for ${scanType}`,
    confidence: 0.0,
    nutrients: [],
    model: nextModelSelection(tier, scanType),
    completedAt: now(),
  };
}

async function loadQuotaSnapshot(uid: string): Promise<{ summaryRef: DocumentReference; summary: ScanQuotaSummary }> {
  const summaryRef = db.doc(`users/${uid}/quota/summary`);
  const snapshot = await summaryRef.get();
  const defaultSummary = defaultQuotaSummary(uid, 'free');
  if (!snapshot.exists) {
    return { summaryRef, summary: defaultSummary };
  }

  return { summaryRef, summary: getQuotaSummaryFromDoc(snapshot) };
}

async function loadPlanState(uid: string): Promise<PlanState> {
  const userPlanSnapshot = await db.doc(`users/${uid}/plan/current`).get();
  if (!userPlanSnapshot.exists) {
    return {
      uid,
      tier: 'free',
      source: 'bootstrap',
      hasActiveEntitlement: false,
      updatedAt: now(),
    };
  }
  return toPlanState(uid, (userPlanSnapshot.data() ?? {}) as Record<string, unknown>);
}

export const healthCheck = onCall(
  { region: FUNCTIONS_REGION },
  async (request) => {
    // TODO boundary: this is identity-only and intentionally not gated by App Check.
    const uid = request.auth?.uid;
    return {
      service: 'nutrition-snap-backend',
      environment: process.env.FUNCTIONS_EMULATOR ? 'local' : 'production',
      requesterUid: uid ?? null,
      now: now().toDate().toISOString(),
      version: process.env.FUNCTION_VERSION ?? '0.0.0',
      appCheck: Boolean(request.app?.appId),
    };
  },
);

export const startScan = onCall(
  { region: FUNCTIONS_REGION },
  async (request) => {
    // TODO boundary: Auth + App Check required; backend owns scan quota checks and R2 object path assignment.
    const uid = assertAuthenticated(request);
    assertAppCheck(request);

    const scanType = resolveScanType(request.data?.scanType);
    const contentType = typeof request.data?.contentType === 'string' ? request.data.contentType : 'image/jpeg';

    const scanId = typeof request.data?.scanId === 'string' && request.data.scanId
      ? request.data.scanId
      : `scan_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

    const { summaryRef, summary } = await loadQuotaSnapshot(uid);
    const planState = await loadPlanState(uid);
    const effectiveSummary: ScanQuotaSummary = {
      ...summary,
      tier: planState.tier,
      monthlyLimit: PLAN_TIER_DEFAULTS[planState.tier].monthlyScans,
      dailyLimit: PLAN_TIER_DEFAULTS[planState.tier].dailyScans,
      updatedAt: now(),
    };

    if (!planState.hasActiveEntitlement && isPaidTier(planState.tier)) {
      throw new HttpsError('permission-denied', 'Premium entitlement not active for this user.');
    }

    const check = quotaCanReserve(effectiveSummary);
    if (!check.canReserve) {
      throw new HttpsError('resource-exhausted', check.reason ?? 'Quota exceeded');
    }

    const r2Key = scanUploadKey(uid, scanType, scanId, contentType);
    const model = nextModelSelection(effectiveSummary.tier, scanType);
    const nowTimestamp = now();
    const uploadDate = todayKey(nowTimestamp.toDate());
    const dailyWindow = effectiveSummary.dailyWindows[uploadDate] ?? {
      date: uploadDate,
      used: 0,
      reserved: 0,
      failed: 0,
    };
    const updatedDailyWindow: DailyQuotaWindow = {
      ...dailyWindow,
      reserved: dailyWindow.reserved + 1,
    };
    const updatedQuota: ScanQuotaSummary = {
      ...effectiveSummary,
      monthlyReserved: effectiveSummary.monthlyReserved + 1,
      dailyWindows: { ...effectiveSummary.dailyWindows, [uploadDate]: updatedDailyWindow },
      updatedAt: nowTimestamp,
    };

    const scanRef = db.doc(`users/${uid}/${firestoreCollections.scans}/${scanId}`);
    const scanDoc: ScanReservation = {
      uid,
      scanId,
      scanType,
      planTierAtReserve: effectiveSummary.tier,
      quotaReservedAt: nowTimestamp,
      quotaReservedBy: 'backend',
      status: 'upload_url_issued',
      lifecycle: [
        buildLifecycleTransition('reserved', 'backend', 'Initial reservation'),
        buildLifecycleTransition('upload_url_issued', 'backend', 'R2 upload URL issued'),
      ],
      r2: {
        scanId,
        uid,
        bucket: functionConfig.r2Bucket,
        key: r2Key,
        contentType,
        sizeBytes: 0,
        retentionClass: isPaidTier(effectiveSummary.tier) ? 'retain' : 'delete_after_success',
        createdAt: nowTimestamp,
        updatedAt: nowTimestamp,
        uploadedBy: 'app',
      },
      quota: {
        monthKey: monthKey(nowTimestamp.toDate()),
        summary: updatedQuota,
        model,
        note: 'scan reservation created',
      },
    };

    // TODO: Use transaction for full race safety in real deployment.
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(scanRef);
      if (existing.exists) {
        throw new HttpsError('already-exists', `Scan ${scanId} already exists.`);
      }
      tx.set(summaryRef, updatedQuota, { merge: true });
      tx.set(scanRef, scanDoc);
    });

    const upload = fakeSignedUploadUrl(r2Key, contentType);
    return {
      scanId,
      uid,
      planTier: effectiveSummary.tier,
      status: 'upload_url_issued',
      remainingMonthly: check.remainingMonthly - 1,
      remainingDaily: check.remainingDaily - 1,
      upload,
      r2ObjectKey: r2Key,
      uploadExpiresAt: upload.expiresAt.toDate().toISOString(),
    };
  },
);

export const getR2SignedUploadUrl = onCall(
  { region: FUNCTIONS_REGION },
  async (request) => {
    // TODO boundary: Auth + App Check required; backend owns all signed URL generation.
    const uid = assertAuthenticated(request);
    assertAppCheck(request);

    const scanId = typeof request.data?.scanId === 'string' ? request.data.scanId : '';
    if (!scanId) {
      throw new HttpsError('invalid-argument', 'scanId is required');
    }

    const scanRef = db.doc(`users/${uid}/${firestoreCollections.scans}/${scanId}`);
    const snapshot = await scanRef.get();
    if (!snapshot.exists) {
      throw new HttpsError('not-found', `Unknown scanId: ${scanId}`);
    }

    const scanDoc = snapshot.data() as ScanReservation;
    if (scanDoc.uid !== uid) {
      throw new HttpsError('permission-denied', 'Scan does not belong to caller');
    }
    const url = fakeSignedUploadUrl(scanDoc.r2.key, scanDoc.r2.contentType);
    return {
      scanId,
      url: url.url,
      method: url.method,
      headers: url.headers,
      expiresAt: url.expiresAt.toDate().toISOString(),
    };
  },
);

export const processScan = onCall(
  { region: FUNCTIONS_REGION },
  async (request) => {
    // TODO Auth + App Check required: process endpoint is trusted-server owned.
    const uid = assertAuthenticated(request);
    assertAppCheck(request);
    const scanId = typeof request.data?.scanId === 'string' ? request.data.scanId : '';
    if (!scanId) {
      throw new HttpsError('invalid-argument', 'scanId is required');
    }

    const scanRef = db.doc(`users/${uid}/${firestoreCollections.scans}/${scanId}`);
    const snapshot = await scanRef.get();
    if (!snapshot.exists) {
      throw new HttpsError('not-found', `Unknown scanId: ${scanId}`);
    }

    const current = snapshot.data() as ScanReservation;
    if (current.uid !== uid) {
      throw new HttpsError('permission-denied', 'Scan does not belong to caller');
    }

    if (current.status !== 'reserved' && current.status !== 'upload_url_issued' && current.status !== 'uploaded') {
      throw new HttpsError('failed-precondition', 'Scan is not in a processable state');
    }

    await scanRef.set(
      {
        status: 'processing' as const,
        model: nextModelSelection(current.planTierAtReserve, current.scanType),
        lifecycle: [...current.lifecycle, buildLifecycleTransition('processing', 'scan_worker', 'placeholder processing')],
        lastHeartbeat: now(),
        updatedAt: now(),
      },
      { merge: true },
    );

    return {
      scanId,
      status: 'processing',
      message: 'Processing started (placeholder). Replace with real scan worker invocation.',
      estimatedResultTtlMinutes: functionConfig.scanResultTimeoutMinutes,
    };
  },
);

export const finalizeScan = onCall(
  { region: FUNCTIONS_REGION },
  async (request) => {
    // TODO Auth + App Check required: finalization consumes quota and should only happen post-processing.
    const uid = assertAuthenticated(request);
    assertAppCheck(request);

    const scanId = typeof request.data?.scanId === 'string' ? request.data.scanId : '';
    const success = request.data?.success !== false;
    if (!scanId) {
      throw new HttpsError('invalid-argument', 'scanId is required');
    }
    if (success && typeof request.data?.result !== 'object') {
      throw new HttpsError('invalid-argument', 'result payload is required when success=true');
    }

    const scanRef = db.doc(`users/${uid}/${firestoreCollections.scans}/${scanId}`);
    const summaryRef = db.doc(`users/${uid}/quota/summary`);
    const nowTimestamp = now();

    await db.runTransaction(async (tx) => {
      const scanSnapshot = await tx.get(scanRef);
      const summarySnapshot = await tx.get(summaryRef);

      if (!scanSnapshot.exists) {
        throw new HttpsError('not-found', `Unknown scanId: ${scanId}`);
      }

      const scan = scanSnapshot.data() as ScanReservation & { result?: ScanResultPayload };
      if (scan.uid !== uid) {
        throw new HttpsError('permission-denied', 'Scan does not belong to caller');
      }
      if (scan.status === 'completed' || scan.status === 'refunded') {
        return;
      }
      if (scan.status === 'failed' && success) {
        // Allow idempotent success attempts only after a fresh state.
        throw new HttpsError('failed-precondition', 'Cannot finalize scan after permanent failure state');
      }

      const summary = summarySnapshot.exists
        ? getQuotaSummaryFromDoc(summarySnapshot)
        : defaultQuotaSummary(uid, scan.planTierAtReserve);

      const currentDay = todayKey(nowTimestamp.toDate());
      const windows = { ...(summary.dailyWindows ?? {}) };
      const day = windows[currentDay] ?? {
        date: currentDay,
        used: 0,
        reserved: 0,
        failed: 0,
      };

      const updateScanState: Partial<ScanReservation> = {
        status: success ? 'completed' : 'failed',
        lifecycle: [...scan.lifecycle, buildLifecycleTransition(success ? 'completed' : 'failed', 'scan_worker', 'scan finalized by backend placeholder')],
      };

      if (success) {
        const nextResult = request.data?.result as ScanResultPayload | undefined;
        tx.update(scanRef, {
          ...updateScanState,
          result: nextResult ?? makePlaceholderResult(scanId, uid, scan.scanType, scan.planTierAtReserve),
          finalizedAt: nowTimestamp,
          updatedAt: nowTimestamp,
        });
        const updatedSummary: ScanQuotaSummary = {
          ...summary,
          monthlyReserved: Math.max(summary.monthlyReserved - 1, 0),
          monthlyUsed: summary.monthlyUsed + 1,
          dailyWindows: {
            ...summary.dailyWindows,
            [currentDay]: {
              ...day,
              reserved: Math.max(day.reserved - 1, 0),
              used: day.used + 1,
            },
          },
          updatedAt: nowTimestamp,
        };
        tx.set(summaryRef, updatedSummary, { merge: true });
      } else {
        tx.update(scanRef, { ...updateScanState, updatedAt: nowTimestamp });
        const updatedSummary: ScanQuotaSummary = {
          ...summary,
          monthlyReserved: Math.max(summary.monthlyReserved - 1, 0),
          dailyWindows: {
            ...summary.dailyWindows,
            [currentDay]: {
              ...day,
              reserved: Math.max(day.reserved - 1, 0),
              failed: day.failed + 1,
            },
          },
          updatedAt: nowTimestamp,
        };
        tx.set(summaryRef, updatedSummary, { merge: true });
      }
    });

    return { scanId, status: success ? 'completed' : 'failed', finalizedBy: uid, finalizedAt: nowTimestamp.toDate().toISOString() };
  },
);

export const refundScan = onCall(
  { region: FUNCTIONS_REGION },
  async (request) => {
    // TODO Auth + App Check required: refund endpoint must only be usable by trusted server flows.
    const uid = assertAuthenticated(request);
    assertAppCheck(request);

    const scanId = typeof request.data?.scanId === 'string' ? request.data.scanId : '';
    if (!scanId) {
      throw new HttpsError('invalid-argument', 'scanId is required');
    }

    const scanRef = db.doc(`users/${uid}/${firestoreCollections.scans}/${scanId}`);
    const summaryRef = db.doc(`users/${uid}/quota/summary`);
    const nowTimestamp = now();

    await db.runTransaction(async (tx) => {
      const scanSnapshot = await tx.get(scanRef);
      const summarySnapshot = await tx.get(summaryRef);

      if (!scanSnapshot.exists) {
        throw new HttpsError('not-found', `Unknown scanId: ${scanId}`);
      }
      const scan = scanSnapshot.data() as ScanReservation & { refundedAt?: string };
      if (scan.uid !== uid) {
        throw new HttpsError('permission-denied', 'Scan does not belong to caller');
      }
      if (scan.status === 'refunded' || scan.status === 'completed') {
        return;
      }

      const summary = summarySnapshot.exists
        ? getQuotaSummaryFromDoc(summarySnapshot)
        : defaultQuotaSummary(uid, scan.planTierAtReserve);
      const currentDay = todayKey(nowTimestamp.toDate());
      const day = summary.dailyWindows[currentDay] ?? { date: currentDay, used: 0, reserved: 0, failed: 0 };

      const updatedSummary: ScanQuotaSummary = {
        ...summary,
        monthlyReserved: Math.max(summary.monthlyReserved - 1, 0),
        dailyWindows: {
          ...summary.dailyWindows,
          [currentDay]: {
            ...day,
            reserved: Math.max(day.reserved - 1, 0),
          },
        },
        updatedAt: nowTimestamp,
      };
      tx.set(summaryRef, updatedSummary, { merge: true });
      tx.update(scanRef, {
        status: 'refunded',
        refundedAt: nowTimestamp.toDate().toISOString(),
        lifecycle: [...scan.lifecycle, buildLifecycleTransition('refunded', 'backend', 'quota refunded placeholder')],
        updatedAt: nowTimestamp,
      });
    });

    return { scanId, refundedAt: nowTimestamp.toDate().toISOString() };
  },
);

export const revenuecatWebhook = onRequest({ region: FUNCTIONS_REGION }, async (req, res) => {
  // TODO boundary: RevenueCat webhook must include shared-secret verification before any writes.
  if (req.method !== 'POST') {
    res.status(405).send('Method not allowed');
    return;
  }

  const providedSecret =
    req.get('x-revenuecat-shared-secret') ||
    req.get('authorization')?.replace(/^Bearer\s+/i, '') ||
    req.body?.secret ||
    '';

  if (!envSecretKeys.revenueCatWebhookSecret) {
    res.status(500).send('Webhook secret is not configured.');
    return;
  }
  if (!providedSecret || providedSecret !== envSecretKeys.revenueCatWebhookSecret) {
    res.status(401).send('Unauthorized webhook request');
    return;
  }

  const event = req.body as RevenueCatWebhookEvent;
  if (!event?.id) {
    res.status(400).send('Invalid webhook payload');
    return;
  }

  const userId =
    event.event_data?.app_user_id ||
    event.subscriber?.app_user_id ||
    event.event_data?.original_app_user_id ||
    event.subscriber?.original_app_user_id;

  if (!userId) {
    res.status(400).send('Missing app_user_id');
    return;
  }

  const isEntitlementActive = ['INITIAL_PURCHASE', 'RENEWAL', 'UNCANCELLATION', 'BILLING_ISSUE'].includes(event.event_type || '');
  const productId = event.event_data?.product_id ?? '';
  const paidTier: PlanTier = /year|annual/i.test(productId) ? 'premiumYearly' : 'premiumMonthly';
  const userPlanRef = db.doc(`users/${userId}/plan/current`);
  const webhookRef = db.doc(`users/${userId}/webhooks/${firestoreCollections.revenuecat}/${event.id}`);

  await db.runTransaction(async (tx) => {
    tx.set(webhookRef, {
      ...event,
      receivedAt: now(),
      source: 'revenuecat',
    });
    tx.set(userPlanRef, {
      uid: userId,
      tier: isEntitlementActive ? paidTier : 'free',
      source: 'revenuecat',
      hasActiveEntitlement: isEntitlementActive,
      updatedAt: now(),
    }, { merge: true });
  });

  res.status(200).send({ ok: true });
});
