# Nutrition Snap — Product Design Document

> **Working title:** Nutri Snap
> **Status:** v0 design, pre-build, architecture merged
> **Author:** Phat Nguyen
> **Last updated:** 2026-06-11

---

## 1. Vision

A calm, bilingual (Japanese / English) iOS app that turns the everyday habit of
photographing meals into **effortless, non-judgmental nutrition awareness**.

You snap a photo of anything you eat or drink → AI estimates the nutrition →
a color-coded calendar shows how each day compares to *your* personal target.
No tedious data entry, no guilt — just gentle awareness that builds a habit.

Japan-first in spirit (strong photo-food culture, weak incumbents), architected
bilingual from day one.

---

## 2. Positioning & wedge

Photo→nutrition is a crowded, well-funded space: **Cal AI, MyFitnessPal,
SnapCalorie, Foodvisor, Yazio**. "AI analyzes your food photo" is *table stakes*,
not a differentiator.

**Our wedge: the gentle nutrition coach — the anti-MyFitnessPal.**
- Calm, warm, non-judgmental. *Awareness*, not calorie-policing.
- Low-friction, illustration-light, photo-rich.
- **Forgiving on accuracy** — the positioning makes "roughly right" acceptable,
  which is essential because photo estimation is inherently fuzzy.

**Durable advantage = market knowledge of Japan** (design taste alone is
copyable). Incumbents are US-centric and weak on Japanese cuisine + nutrition norms.

---

## 3. Market & localization

- **Bilingual JA + EN at launch**, Japan-first emphasis.
- LLM outputs in the user's language natively — no translation pipeline.
- UI strings via iOS **String Catalogs (`.xcstrings`)**.
- Nutrition standard is **locale-agnostic** (personalized formula, §4) — avoids
  maintaining two national standards (MHLW vs US RDA).
- **Japan advantage:** OCR path for コンビニ / packaged-food 栄養成分表示 labels.

---

## 4. Nutrition model

### What we track
- **Primary:** calories (kcal)
- **Secondary:** protein, carbs, fat (the 3 macros)
- **Focused micronutrients (added 2026-06-06):** fiber, omega-3, vitamin C,
  vitamin A, zinc, iron, magnesium — estimated from the photo or extracted from
  nutrition labels, judged on **rolling-average adequacy vs reference, never daily
  pass/fail**. Reference = Japanese MHLW DRI (adult-male default until onboarding
  personalizes). *Supersedes the original "micronutrients not tracked" decision —
  the app is now a personal long-term-health/beauty tool, not just calorie tracking.*
- **Still out:** other micros (B12, D, …) are photo-unreliable; the honest path
  there is supplement logging + periodic bloodwork (future).
- **"Good/bad" → a gentle balance note**, not a hard score.

### Recommended daily amount = personalized (Mifflin–St Jeor)
Locale-agnostic, accurate per person, industry standard, free, ~10 lines of code.

**BMR** (W = weight kg, H = height cm, A = age years):
- Men:   `BMR = 10·W + 6.25·H − 5·A + 5`
- Women: `BMR = 10·W + 6.25·H − 5·A − 161`

**TDEE = BMR × activity factor:**
| Activity | Factor |
|---|---|
| Sedentary | 1.2 |
| Light | 1.375 |
| Moderate | 1.55 |
| Active | 1.725 |
| Very active | 1.9 |

**Goal adjustment:** Maintain ×1.0 · Lose −15% (~−500 kcal) · Gain +10–15%

**Target macros (default split):** Protein 20% · Fat 30% · Carbs 50% of target kcal.
(grams: protein = kcal·0.20 / 4 · carbs = kcal·0.50 / 4 · fat = kcal·0.30 / 9)

**Onboarding collects:** sex, age, height, weight, activity level, goal.
Skippable with a smart default → see Open Question #3.

---

## 5. Key user flows

### 5.1 Onboarding
Welcome → Sign in with Apple → body-stats form → compute target → "you're set" → Home.
Skippable: assume a sane default target, refine later in Settings.

For the production subscription app, prefer real sign-in before purchase. Anonymous
usage is acceptable only if the account-linking and purchase-recovery path is explicit.

Recommended identity rule:
```text
Firebase Auth UID = RevenueCat App User ID = primary user ID in backend records
```

First-time app start:
```text
User opens app
  → app creates or signs into Firebase Auth user
  → app identifies the same UID to RevenueCat
  → app fetches RevenueCat offering for paywall UI
  → app reads user plan and quota summary from backend
  → user lands on Snap screen
```

RevenueCat local state may improve UI speed, but backend Firestore entitlement is
the source of truth for scan access.

### 5.2 Capture / scan loop — *the core*
1. **Home = a large camera viewfinder** (the dominant UI).
2. Snap a photo (or pick from library).
3. App compresses the image.
4. App asks the backend to start a scan.
5. Backend verifies Firebase Auth, App Check, entitlement, daily quota, monthly quota,
   image-size policy, and concurrent-processing policy.
6. Backend reserves one scan credit and returns a temporary Cloudflare R2 upload URL.
7. App uploads the image directly to private R2 storage.
8. App asks backend to process the scan.
9. Backend fetches the image from R2, chooses an LLM policy by plan and scan type,
   calls the provider through the model router, validates the response, and normalizes
   the result.
10. Backend saves the structured result, finalizes quota usage, updates the day rollup,
    and applies the image-retention policy.
11. Result is **auto-logged** as a warm summary card
    *("Lunch logged · ~520 kcal · looks balanced")* with a **quiet Edit affordance**.
12. **Low confidence** → card gently invites a tap *("Tap to confirm what this was")*
    instead of asserting.

> **Design tenet:** the Edit affordance is *present but quiet* — discoverable, never in the way.
> Frictionless for the 80%, correctable for the 20%.

### 5.3 Scan failures and quota limits
- Failed uploads, failed OCR/LLM attempts, invalid images, and abandoned scan
  reservations do **not** consume quota.
- A scan only counts after successful processing and saved structured nutrition data.
- If quota is exceeded, the backend rejects the scan before upload and the app shows
  a paywall or wait-until-reset state.
- If a completed result is usable but uncertain, it counts as a successful scan and
  the UI asks for confirmation.

### 5.4 Journal (calendar / diary)
- Month grid; each day filled with a **calm divergent band color** = calories vs *your* target:
  | State | Color | Feeling |
  |---|---|---|
  | Under | soft muted cool | "a light day" |
  | In range | warm clay / on-track (hero) | "on track" |
  | Over | warm amber (**never red**) | "a fuller day" |
  | No log | neutral / empty | — |
- **Discrete buckets, not a continuous gradient** (calm > anxious precision).
- **Tap a day → day detail:** photo grid of that day's meals + totals vs target +
  balance note. *(The photo grid is the emotional heart — food memories.)*
- Free users may keep structured history and thumbnails, but original image retention
  is a paid-plan feature.

### 5.5 Trends (added 2026-06-06)
A third tab for calm, nutrition-only insights over time: a daily-calorie trend, a
**nutrient sufficiency panel** (the focused 8, rolling-average adequacy vs reference —
see §4), a days-on-track rhythm, and gentle *observational* patterns ("weekends tend to
run fuller", never "you overeat"). Most trend computation should be on-device from
Firestore data; an opt-in "reflect on my week" makes one backend-mediated LLM text call.

App layout is now **3 tabs with a raised center camera: Trends ← Snap → Journal.**

### 5.6 Purchase and subscription flows
Purchase flow:
```text
User views paywall
  → app starts RevenueCat purchase
  → App Store confirms transaction
  → RevenueCat updates customer entitlement
  → RevenueCat sends webhook to Cloud Function
  → backend updates Firestore user plan
  → app refreshes user plan and quota
```

If the webhook is delayed, the app may call a backend sync endpoint; the backend checks
RevenueCat customer state and updates Firestore if needed.

Subscription expiration flow:
```text
Subscription expires or billing fails
  → RevenueCat sends webhook
  → backend updates user plan to Free or grace state
  → backend lowers future scan quota
  → backend disables paid-only model routing
  → backend may schedule image-retention downgrade
```

Do not immediately delete paid user history on expiration. Use a grace period before
deleting original images or requiring resubscription for image-history access.

---

## 6. AI and scan pipeline

### Model strategy
- **Default provider:** Gemini, cheap/fast vision tier (Flash-class) for MVP.
- **Backend abstraction:** all model calls go through a Cloud Functions model router,
  not directly from the client.
- **Future providers:** Claude or another LLM can be added behind the same router.
- **Prompt ownership:** prompt templates and output validation live server-side.
- **Fallback:** stronger model or second provider only when the user's tier and the
  scan policy allow it.

The backend should not be hard-wired to Gemini:
```text
scan request
  → backend reads user tier and scan type
  → backend chooses model policy
  → backend calls Gemini, Claude, or another provider
  → backend normalizes result into one schema
```

### Scan types
| Scan type | Product behavior | Confidence posture |
|---|---|---|
| Nutrition label | OCR 栄養成分表示 and extract near-exact values | Higher confidence expected |
| Packaged food image | Extract brand/product text if visible | User confirmation recommended |
| Meal photo | Estimate foods, portions, calories, macros, focused micros | Always present as estimate |

Important product principle:
```text
Do not present meal-photo micronutrients as precise truth.
Present them as estimates with confidence and editable fields.
```

### Structured result contract
One successful scan produces:
```text
{
  scanType: "meal_photo" | "nutrition_label" | "packaged_food",
  source: "vision" | "ocr" | "hybrid",
  items: [
    {
      name,
      portion,
      kcal,
      protein,
      carbs,
      fat,
      fiber,
      omega3,
      vitaminC,
      vitaminA,
      zinc,
      iron,
      magnesium,
      confidence
    }
  ],
  totals: { kcal, protein, carbs, fat, fiber, omega3, vitaminC, vitaminA, zinc, iron, magnesium },
  balanceNote,
  needsUserConfirmation,
  modelMetadata: { provider, model, fallbackUsed, costEstimate, processingMs }
}
```

### Cost reality
Every successful scan can trigger one or more paid model calls. This drives:
- Backend-only LLM access.
- Monthly and daily scan caps.
- Tier-specific fallback policy.
- Per-scan cost logging from the first release.
- No unlimited scanning plan.

---

## 7. Design system

**Aesthetic: Anthropic-*inspired* warm-minimal — but our own brand, not a clone.**
- Cream/ivory backgrounds · ONE warm coral/clay accent · slate-ink text ·
  generous whitespace · humanist typeface.
- The warm clay accent **is** the calendar "on-track" color — aesthetic and
  positioning are the same decision.

**Illustrations:** used **sparingly** (onboarding, empty states, celebration),
**AI-generated** in one consistent style, lightly refined. Users' own food photos
carry the visual richness everywhere else.

**In SwiftUI:** a `Theme` + Color-assets token layer. (Concrete hex tokens TBD at build.)

---

## 8. Technical architecture

### Architecture principles
1. **Backend owns trust decisions.** The client can show plan and quota UI, but the
   backend enforces paid access, quota, model choice, image retention, and scan finalization.
2. **Charge and limit by successful scan.** Failed uploads, failed OCR, invalid images,
   and abandoned reservations are refunded or ignored.
3. **Decouple infrastructure from LLM provider.** Firebase is the app/backend platform;
   Gemini is the initial model provider behind a router.
4. **Store images separately from app metadata.** Firestore stores structured data;
   Cloudflare R2 stores private image objects and thumbnails.
5. **Prefer quotas over unlimited plans.** Unlimited scanning creates uncontrolled LLM
   cost risk.

### Stack
- **Client:** Native **Swift + SwiftUI** (iOS-first). Learning iOS is an explicit goal.
- **Identity:** Firebase Auth. Firebase UID is the canonical user ID and RevenueCat App User ID.
- **Backend:** Firebase Cloud Functions + App Check as the trusted policy layer.
- **Data:** Firestore with offline persistence as the single structured app store —
  local-first feel + cloud sync, **no SwiftData** (avoids a second store + migration).
- **Images:** Cloudflare R2 private bucket with temporary signed upload/read URLs.
- **Purchases:** RevenueCat for App Store subscription purchase, restore, entitlement
  state, and webhooks.
- **AI:** Provider-agnostic LLM router in Cloud Functions; Gemini first.
- **Native integrations (v2):** HealthKit (read weight/activity, write dietary energy +
  macros) · WidgetKit (today-vs-target widget) · App Intents/Siri ("log my lunch").

### System data path
```text
SwiftUI
  → Firebase Auth + App Check
  → RevenueCat customer identity / offerings
  → Cloud Function: start scan, verify quota, reserve credit
  → R2 signed upload URL
  → Cloud Function: process scan
  → LLM provider router
  → normalized structured result
  → Firestore scan + day rollup + usage counters
  → app renders result and calendar
```

### Core component responsibilities
**Mobile app**
- User login and account creation.
- Display current plan and remaining scan quota.
- Display paywall and trigger purchases through RevenueCat.
- Capture or upload food images.
- Compress images before upload.
- Request scan permission from backend.
- Upload image to R2 using a temporary signed URL.
- Display scan result and allow user correction.

The app does **not** call LLM providers directly, write usage counters, decide plan
access, hold R2 credentials, or hold LLM credentials.

**Cloud Functions**
- Validate Firebase Auth and App Check.
- Receive and verify RevenueCat webhooks.
- Maintain entitlement state in Firestore.
- Enforce scan quota and rate limits.
- Create scan reservations.
- Generate temporary R2 upload/read URLs.
- Call LLM providers through the router.
- Validate and normalize model output.
- Finalize or refund scan quota.
- Delete or retain image files based on tier.

**Firestore**
- Users, profile, targets, plan summaries.
- RevenueCat-derived entitlement state.
- Daily/monthly scan usage counters.
- Scan lifecycle and structured nutrition results.
- Day rollups for fast calendar rendering.
- Operational metrics, abuse signals, webhook history.

**Cloudflare R2**
- Original uploaded images.
- Thumbnails for history.
- Optional internal-only debug artifacts.
- Private object storage only; no public user food-image bucket.

**RevenueCat**
- Fetch paywall offerings.
- Start subscription purchases and restore purchases.
- Track subscription entitlements.
- Send subscription lifecycle events to backend webhooks.

RevenueCat is the purchase system, not the quota system. RevenueCat answers whether
a user has an active entitlement; the backend answers what plan, quota, model policy,
and storage policy the user receives.

### Firestore model
```text
users/{uid}
  profile: { displayName, locale, sex, age, heightCm, weightKg, activityLevel, goal }
  targets: { kcal, protein, carbs, fat, fiber, omega3, vitaminC, vitaminA, zinc, iron, magnesium }
  plan: { tier, status, revenueCatAppUserId, entitlementId, currentPeriodEnd, graceUntil }
  createdAt
  updatedAt

users/{uid}/usage/{yyyy-MM}
  scansUsed
  scansReserved
  daily: { yyyy-MM-dd: { scansUsed, scansReserved, failedAttempts } }
  updatedAt

users/{uid}/scans/{scanId}
  status: "created" | "reserved" | "upload_url_issued" | "uploaded" | "processing" |
          "completed" | "failed" | "refunded" | "expired" | "deleted"
  capturedAt
  completedAt
  scanType: "meal_photo" | "nutrition_label" | "packaged_food"
  source: "vision" | "ocr" | "hybrid"
  edited: bool
  r2: { originalKey, thumbnailKey, retentionPolicy, originalDeletedAt }
  quota: { reserved: bool, finalized: bool, refunded: bool, tierAtScanTime }
  model: { provider, model, fallbackUsed, inputTokens, outputTokens, costEstimate, processingMs }
  items: [ { name, portion, kcal, protein, carbs, fat, fiber, omega3, vitaminC,
             vitaminA, zinc, iron, magnesium, confidence } ]
  totals: { kcal, protein, carbs, fat, fiber, omega3, vitaminC, vitaminA, zinc, iron, magnesium }
  balanceNote: string
  needsUserConfirmation: bool

users/{uid}/days/{yyyy-MM-dd}          ← rollup for a fast calendar
  totals: { kcal, protein, carbs, fat, fiber, omega3, vitaminC, vitaminA, zinc, iron, magnesium }
  entryCount
  band: "under" | "in" | "over"
  confirmationCount
  updatedAt

webhooks/revenuecat/{eventId}
  receivedAt
  processedAt
  uid
  eventType
  status
```

The **per-day rollup doc** makes the NoSQL calendar fast — one tiny read per day
instead of querying every meal. Maintain it in the trusted backend when a scan is
completed or edited.

### Data ownership and trust boundaries
The client can read:
- Own user profile.
- Own current plan summary.
- Own quota summary.
- Own scan results.
- Own signed image read URLs, if the active tier allows image history.

The client cannot directly write:
- Plan or entitlement.
- Quota counters.
- Model used.
- LLM cost.
- Final scan status.
- R2 object paths.
- Backend-owned retention policy.

Only backend functions hold:
- RevenueCat webhook secret.
- R2 access keys.
- LLM API keys.
- Admin credentials.

### Quota and rate-limit model
Use multiple limits:
- Monthly scan limit controls unit economics.
- Daily scan limit controls bursts and abuse.
- Image size limit controls storage and model token cost.
- Concurrent processing limit prevents one user from occupying backend capacity.
- Failed attempt limit prevents repeated invalid uploads.

Credit lifecycle:
```text
Requested
  → scan credit is reserved

Uploaded
  → image exists in R2

Processing
  → LLM call is active

Completed
  → reserved credit becomes used credit

Failed
  → reserved credit is refunded

Expired
  → abandoned reservation is refunded by cleanup job
```

This prevents users from starting many parallel scans before quota updates.

### Storage lifecycle
Free user image policy:
```text
After successful scan:
  - keep structured nutrient result
  - optionally keep small thumbnail
  - delete original image
```

Paid user image policy:
```text
After successful scan:
  - keep structured nutrient result
  - keep thumbnail
  - retain original image for history and reprocessing
```

Expired subscription policy:
```text
When user downgrades:
  - stop new paid-tier scans immediately
  - preserve old data during grace period
  - after grace period, remove original images or require resubscription for image history
```

### Security architecture
- All scan operations require Firebase Auth.
- Sensitive callable/backend functions require Firebase App Check.
- RevenueCat webhook endpoint requires shared authorization verification.
- R2 bucket remains private.
- Clients never receive direct R2 credentials or LLM credentials.
- Firestore Security Rules allow user-owned reads/writes only for client-owned fields;
  backend-owned fields are server-maintained.

### Observability and cost controls
Each scan should record:
- User tier at scan time.
- Model used.
- Fallback used or not.
- Input/output token estimate.
- Cost estimate.
- Success or failure.
- Confidence score.
- Processing duration.

Per-user metrics:
- Scans per day and month.
- Failed scans.
- Paid status.
- Estimated gross margin.
- Unusually high usage patterns.

Backend kill switches:
- Disable fallback model globally.
- Lower free quota globally.
- Disable scan processing temporarily.
- Force all users to cheaper model.
- Disable image retention for new scans.

These controls matter because LLM prices, bugs, or abuse patterns can change the cost
profile quickly.

### System states
User states:
```text
Anonymous / trial
Free registered
Premium active
Premium grace period
Expired / downgraded
Suspended / abuse-limited
```

Scan states:
```text
Created
Reserved
Upload URL issued
Uploaded
Processing
Completed
Failed
Refunded
Expired
Deleted
```

Subscription states:
```text
No entitlement
Active entitlement
Billing issue
Cancelled but active until expiration
Expired
Refunded
Product changed
```

### Bilingual data note
Store nutrition as **structured numbers** + a display name. Cross-language food dedup
(a canonical food ID so "親子丼" and "oyakodon" aren't two foods) is a **v2** refinement;
MVP stores the name as returned in the user's locale.

---

## 9. Monetization and tier model

### Launch tiers
Launch with only:
```text
Free
Premium monthly
Premium yearly
```

Do not launch Power, scan packs, family plans, or unlimited plans until real scan
behavior is known.

### Free
Purpose: acquisition and product trial.
- Low monthly scan limit.
- Daily burst limit.
- Cheapest reliable model.
- No fallback by default.
- Structured nutrition history.
- Original image deleted after extraction.
- Optional thumbnail retention.

### Premium
Purpose: main paid plan.
- Scan limit high enough for regular personal use, still capped.
- Better default model or retry policy.
- One fallback when JSON is invalid or confidence is low.
- Image history enabled.
- Original image retention for history and reprocessing.

### Future Power tier
Purpose: heavy users and early monetization test.
- Higher scan cap.
- Priority processing if queueing is introduced.
- Stronger fallback policy.
- Richer export and analysis features.

### Paywall gates
The paywall should appear when the user:
- Reaches monthly scan limit.
- Reaches daily scan limit.
- Attempts enhanced scanning.
- Attempts image history on Free tier.
- Attempts export or advanced analysis.

The most important paid feature is not simply "more storage." It is:
```text
More successful LLM scans with better extraction quality and history retention.
```

---

## 10. MVP and rollout plan

### Product MVP
**In v1:** camera capture → backend scan gate → R2 upload → LLM analysis → auto-log +
edit → today total vs target → calendar w/ calm fill → day photo-diary → minimal
onboarding → Free/Premium quota policy.

**One language polished first** (architected for both).

For first production release, keep scope narrow:
```text
Plans:
  Free
  Premium monthly
  Premium yearly

Scan types:
  Nutrition labels
  Packaged food images
  Meal photos as estimates, with clear confidence and edit affordance

Avoid at launch:
  Power tier
  Scan packs
  Family plans
  Unlimited scans
  Complex analytics
  Fully automated meal-photo micronutrient claims without confidence/editing
```

### Build order — each step is a usable milestone
1. **Static SwiftUI shell** — three tabs (Trends, Snap, Journal), theme tokens, fake data.
   *Learn SwiftUI layout, zero backend.*
2. **Local capture → mock result → render** — prove the core UX with fake data.
3. **Firebase Auth + Firestore profile** — Sign in with Apple; user profile and targets.
4. **Cloud Functions backend shell + App Check** — signed-in user recognized across app
   and backend.
5. **Quota gate** — backend checks plan, daily quota, monthly quota, reserves scan credit,
   and rejects over-quota scans even if the client is modified.
6. **R2 upload path** — backend creates signed upload URL; client uploads image; backend
   owns object path; expired reservations are cleaned up.
7. **LLM processing** — backend fetches image, chooses model, calls Gemini first,
   normalizes result, finalizes or refunds scan credit.
8. **Persist + calendar** — scans and day rollups drive journal and trends. *Now you use it daily.*
9. **RevenueCat subscription identity** — RevenueCat App User ID = Firebase UID;
   sandbox purchase updates backend plan through webhook.
10. **Paid differentiation** — Premium scan quota, image retention, retry/fallback policy,
    Free original deletion, paywall at quota limit.
11. **Onboarding + target math** — Mifflin–St Jeor + calm color thresholds.
12. **Production cost controls** — per-scan cost estimate, fallback kill switch, quota
    override, suspicious usage detection.

---

## 11. Deferred to v2+

HealthKit sync · home-screen widget · reminders / notifications · second-language full
polish · Power tier · scan packs · family plans · richer exports · social / sharing ·
canonical food IDs for cross-language dedup · supplement logging · periodic bloodwork
notes · Android.

---

## 12. Open questions

1. **Error & edge handling** *(parked — resolve next, v1-critical)* — not-food photos,
   low confidence, offline, Gemini/LLM failures, upload failures, and the *gentle*
   handling of each.
2. **Color thresholds** — proposed: under `<85%`, in-range `85–110%`, over `>110%` of
   target. Confirm.
3. **Onboarding skip vs. default** — reconcile "skippable" with "the calendar needs a
   target." Proposed: skip → sane default (e.g. 2000 kcal) + a gentle nudge to personalize.
4. **Compliance** — "not medical advice" disclaimer · privacy policy · HealthKit privacy
   strings · Japan **APPI** for body data + photos · whether nutrition results are health
   data in launch markets.
5. **Sign-in timing** — require real sign-in before first scan, or allow anonymous trial
   with explicit upgrade/link-account flow?
6. **Original image retention** — retain by default for paid users, make it opt-in, or
   offer per-scan deletion?
7. **Launch scan scope** — labels and packaged food first, or meal photos in the first
   public release?
8. **Acceptable OCR error rate** — what quality threshold is good enough for launch?
9. **Pricing and unit economics** — first paid plan price, monthly scan cap, daily cap,
   maximum acceptable LLM cost per paid user per month.
10. **Cancellation behavior** — what exactly happens to paid image history when a user
    cancels or billing fails?
11. **Data rights** — account deletion and data export requirements from day one.
12. **Launch markets** — Japan-only first, US/Japan together, or broader App Store launch?

---

## 13. Key risks

| Risk | Mitigation |
|---|---|
| Solo founder, first Swift app, ambitious scope → never ships | Thin v1 + milestone build order |
| Per-scan LLM cost at scale | Backend quota reservation + capped plans + cost logging + kill switches |
| Abuse or modified clients bypassing limits | Firebase Auth, App Check, Cloud Functions trust boundary, backend-owned counters |
| Photo estimation accuracy | Forgiving positioning + Edit affordance + OCR labels + confidence posture |
| Paid purchase state drift | RevenueCat webhooks + backend sync endpoint + Firestore entitlement source of truth |
| Image privacy/storage risk | Private R2 bucket + signed URLs + Free original deletion + paid retention grace policy |
| Crowded market | Japan-first + gentle-tone differentiation |

---

## 14. Decision log

| # | Decision | Choice |
|---|---|---|
| 1 | Goal | Product for others (sequenced single-user → multi-user → paid production) |
| 2 | Wedge | Gentle nutrition coach (anti-MyFitnessPal) |
| 3 | Market | Bilingual JA + EN, Japan-first |
| 4 | Nutrition target | Personalized Mifflin–St Jeor; calories + P/C/F + focused micros |
| 5 | Capture | Auto-log with quiet, optional correction |
| 6 | Calendar | Calm divergent fill (under/in-range/over); tap → photo-grid day diary |
| 7 | Stack | Native Swift + SwiftUI |
| 8 | AI | Backend model router; Gemini first; provider-agnostic over time |
| 9 | Backend | Firebase Auth, Firestore, Cloud Functions, App Check |
| 10 | Image storage | Private Cloudflare R2 with signed URLs; Firestore stores metadata only |
| 11 | Purchases | RevenueCat entitlements; backend owns quota and plan policy |
| 12 | Quota | Count successful scans only; reserve/refund credit lifecycle |
| 13 | Tiers | Launch Free + Premium monthly/yearly; no unlimited plan |
| 14 | Data layer | Firestore offline persistence as single structured store; no SwiftData |
| 15 | Visuals | Anthropic-inspired warm-minimal; sparse AI illustration; food photos carry richness |
| 16 | v1 scope | Thin vertical slice with trusted backend scan path and capped monetization |

---

## 15. Technical references

- Firebase App Check for Cloud Functions: https://firebase.google.com/docs/app-check/cloud-functions
- Firebase callable functions: https://firebase.google.com/docs/functions/callable
- Firestore Security Rules: https://firebase.google.com/docs/firestore/security/get-started
- RevenueCat Firebase integration: https://www.revenuecat.com/docs/integrations/third-party-integrations/firebase-integration
- RevenueCat identifying customers: https://www.revenuecat.com/docs/customers/identifying-customers
- RevenueCat webhooks: https://www.revenuecat.com/docs/integrations/webhooks
- RevenueCat entitlements: https://www.revenuecat.com/docs/getting-started/entitlements
- Cloudflare R2 pricing: https://developers.cloudflare.com/r2/pricing/
- Cloudflare R2 CORS and presigned URL behavior: https://developers.cloudflare.com/r2/buckets/cors/
- Cloudflare R2 object uploads: https://developers.cloudflare.com/r2/objects/upload-objects/
