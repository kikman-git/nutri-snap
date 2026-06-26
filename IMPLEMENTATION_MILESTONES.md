# Nutrition Snap Implementation Milestones

> Source of truth: `PRD.md` for product/architecture, `NEXT_SESSION.md` for current
> code status. This file translates both into buildable implementation milestones.
> Updated: 2026-06-12 (worker patches reviewed + verified on simulator; repo restructured
> into a multi-platform monorepo — iOS now lives under `ios/`, future Kotlin app under
> `android/`, shared backend/config/docs at root)

## Current Baseline

Already built and verified:
- M1 static SwiftUI shell with three-tab layout: Trends, Snap, Journal.
- M2 capture/review/analyze/log flow with Gemini behind `MealEstimating`.
- M3 Firestore persistence, offline cache, day rollups, local photo storage, delete flow.
- Live-camera-first Snap UI with simulator fallback to library picker.
- Trends, micronutrient rollups, day detail macros/micros, and memory-safe image downsampling.

Important architecture change now accepted in `PRD.md`:
- Production scan trust moves to Firebase Cloud Functions.
- Image originals move from local-only/Firebase Storage assumptions to private Cloudflare R2.
- Subscription and entitlement state comes from RevenueCat, but backend owns quota policy.
- Client-side direct Gemini remains useful for current dev, but production scan processing
  should migrate behind the backend LLM router.

## v1 Paywall Scope Decision (2026-06-26, grill-resolved) — branch `m6-paywall`

The "add login" task was reframed: **login isn't needed to monetize** (StoreKit bills the
Apple ID; RevenueCat keys off `appUserID = Firebase anon uid`). v1 ships a **server-enforced
paywall on anonymous auth**; Apple/Google sign-in is **deferred**. This compresses the backend
milestones below:

- **Collapse M5 + M6 + M8 + M9** into one lean path: a single `scanMeal(imageBase64, note)`
  callable that verifies Auth + App Check + entitlement + quota, calls Gemini server-side
  (inline bytes), and commits/refunds the credit in one invocation.
- **Skip M7 (Cloudflare R2)** entirely — inline image bytes, photos stay on-device. Revisit R2
  only if paid original-retention becomes a feature.
- **Free tier = 3 *lifetime* scans** (not M6's monthly 20/3). Premium = monthly + annual, each
  with a 7-day Apple free trial; the premium monthly scan cap is retained to bound cost.
- **Paywall UI:** custom SwiftUI (the brand-fit version of M10's "plan UI"), not RevenueCat's
  prebuilt Paywalls.
- Fix the 2026-06-12 review findings as the code goes real (webhook CANCELLATION → active-until-
  expiry, header-only webhook secret, quota read inside the transaction, `enforceAppCheck`,
  `PlanTier.unknown` tolerant decode).
- Still out of v1: account-deletion/export UI (PRD Q#11 — launch item), OCR label path (v2).

## Milestone 4A — Current App Hardening

Goal: make the existing single-user app feel complete enough to keep using while backend
architecture work begins.

Scope:
- Meal edit sheet for the quiet Edit affordance.
- Per-item correction of name, portion, calories, macros, focused micronutrients, and confidence.
- Recalculate totals and day rollups after edits.
- Fix known small quality issues such as the sample "Snack logged" labeling.
- Replace placeholder brand colors if a palette is chosen.

Acceptance:
- A newly logged meal and a Journal meal can both be edited.
- Edited totals persist through Firestore and survive relaunch.
- Calendar/day rollups update after edits.
- Existing delete, capture, Trends, and Journal flows still work.

## Milestone 4B — Personal Targets and Onboarding

Goal: replace static/default targets with user profile-driven targets.

Scope:
- User profile model for sex, age, height, weight, activity level, and goal.
- Mifflin-St Jeor target calculator.
- Default macro split and focused micronutrient reference defaults.
- Skippable onboarding with a sane default target and a Settings/Profile re-entry point.
- Store profile/targets under `users/{uid}` in Firestore.

Acceptance:
- First launch can complete or skip onboarding.
- Targets are computed deterministically from the entered profile.
- Calendar bands and Trends use the stored target.
- Skipping onboarding still produces a valid calendar target.

## Milestone 5 — Trusted Backend Foundation

Goal: establish the server-side trust boundary before moving expensive scan work off-device.

Scope:
- Firebase Cloud Functions workspace.
- Callable or HTTPS endpoints for authenticated backend operations.
- Firebase Auth and App Check validation.
- Firestore server-owned fields and security rules aligned with backend ownership.
- Shared scan status, tier, quota, and result schema.

Acceptance:
- A signed-in app user can call a backend health/identity endpoint.
- Unauthenticated or invalid App Check requests are rejected.
- Firestore rules prevent clients from writing plan, entitlement, quota, model metadata,
  scan final status, and R2 object paths directly.

## Milestone 6 — RevenueCat Entitlements and Quota Gate

Goal: make scan access a backend-enforced decision.

Scope:
- RevenueCat App User ID = Firebase UID.
- RevenueCat webhook receiver with shared-secret validation.
- Firestore plan/entitlement documents.
- Daily/monthly scan quota config for Free and Premium.
- Scan reservation, finalization, refund, and expiry lifecycle.

Acceptance:
- Sandbox purchase updates backend plan state.
- Free users cannot exceed quota even with a modified client.
- Failed or abandoned scans refund the reservation.
- Backend returns a clear quota/paywall reason before image upload.

## Milestone 7 — Cloudflare R2 Image Path

Goal: move original image storage to private object storage without exposing credentials.

Scope:
- R2 bucket and object-key policy.
- Backend-generated signed upload URLs.
- Optional signed read URLs for paid image history.
- Thumbnail strategy.
- Free/Premium/expired retention cleanup.

Acceptance:
- Client uploads an image to R2 through a temporary signed URL.
- Backend owns the object path and records it in Firestore.
- Free successful scans delete original images after extraction.
- Premium scans retain originals and thumbnails according to policy.

## Milestone 8 — Backend LLM Router and Scan Processing

Goal: make successful scans run through backend policy and provider-agnostic model routing.

Scope:
- `processScan` backend endpoint.
- Fetch image from R2.
- Route by user tier and scan type.
- Gemini-first provider adapter with normalized output schema.
- JSON validation, confidence rules, retry/fallback policy, and cost metadata.
- Save structured scan result and update day rollups server-side.

Acceptance:
- A completed backend scan produces the same user-facing nutrition data shape as the
  existing client Gemini path.
- Exactly one successful scan credit is consumed per usable result.
- Low-confidence results are saved with `needsUserConfirmation`.
- Model metadata and estimated cost are recorded.

## Milestone 9 — Client Migration to Production Scan API

Goal: move the app from direct local processing to the trusted production scan path.

Scope:
- Client `ScanService` that starts a scan, uploads to R2, processes it, polls/listens
  for completion, and maps results to current app models.
- Keep `GeminiMealEstimator` only as a dev fallback or test seam.
- Plan/quota state visible in the app.
- Paywall entry points when backend rejects quota.
- Offline and retry UX for upload/process failures.

Acceptance:
- Normal capture flow uses backend scan APIs in production configuration.
- Direct Gemini access is disabled outside debug/dev mode.
- Quota and paywall states appear before upload.
- Existing Snap, Journal, Trends, edit, and delete flows continue to work.

## Milestone 10 — Paid Differentiation and Production Controls

Goal: ship a capped Free/Premium product with cost controls.

Scope:
- Free/Premium monthly/yearly plan UI.
- Premium scan cap, retry/fallback policy, and image history.
- Operational kill switches for fallback, free quota, image retention, and scan processing.
- Per-user/per-scan cost and failure dashboards.
- Account deletion and data export decision implemented if launch market requires it.

Acceptance:
- Free and Premium users have meaningfully different backend policies.
- No unlimited scanning path exists.
- Admin config can lower cost exposure without app release.
- User data deletion path covers Firestore docs and R2 objects.

## Delegated Coding Tasks

The following tasks are intended to be owned by GPT-5.3 Codex worker agents with
disjoint write scopes:

| Agent | Ownership | Initial task | Integration status |
|---|---|---|---|
| Dirac (`019eb4ae-6283-7643-b516-898cefcd3f13`) | `functions/`, backend docs/config only | Scaffold Firebase Cloud Functions backend types and placeholder endpoints for auth/App Check, scan lifecycle, quota, RevenueCat webhook, and R2 signing. | Integrated; `npm run build` passes; reviewed 2026-06-12 (see findings below) |
| Popper (`019eb4ae-921c-7601-ad2f-0266666d39cc`) | `ios/NutritionSnap/Services/PlanService.swift`, `ios/NutritionSnap/Models/PlanModels.swift` only | Add client-side plan/quota models and a mockable service seam that can later call backend quota endpoints. | Integrated; builds; reviewed 2026-06-12 — dormant by design (not wired into UI until M6/M9) |
| Gauss (`019eb4ae-c27a-7b20-9392-712ed29a09ce`) | `ios/NutritionSnap/Features/EditMeal/`, targeted edits in Capture/Calendar/MealStore if needed | Implement meal edit UI and store update path for existing logged meals. | Integrated; **verified end-to-end on simulator 2026-06-12** (sheet prefill → save → cold-relaunch persistence → rollup delta applied exactly once) |

### Review findings (2026-06-12) — fix when the owning milestone starts

Placeholder-stage issues found reviewing the worker patches. None block current use;
all become real before their milestone ships:

- **M6 / `functions/src/index.ts` `revenuecatWebhook`:** `CANCELLATION` immediately sets
  tier `free` — wrong; cancellation only disables auto-renew, entitlement lasts until
  `EXPIRATION`. Map cancellation → still-active-until-period-end.
- **M6 / webhook secret:** accepted from the request **body** (`req.body?.secret`) as a
  fallback — header-only before go-live.
- **M5 / `startScan`:** quota is read **outside** the transaction, so two concurrent calls
  can both reserve the last slot (the in-code TODO acknowledges this). Move read+write
  inside the transaction.
- **M5/M8 / `finalizeScan` + `refundScan`:** client-callable and accept a client-supplied
  result payload — the real scan worker must own finalization (acknowledged TODOs).
- **M5 / App Check:** `assertAppCheck` is env-gated and only checks `request.app` presence;
  use `enforceAppCheck: true` in the callable options for production.
- **M5 / quota windows:** `todayKey` uses UTC, so daily windows roll at UTC midnight, not
  user-local (acceptable for cost control — just intentional, not accidental).
- **M6 / `PlanModels.swift`:** `PlanTier.unknown`'s comment promises forward-compatible
  decoding, but the synthesized `Codable` **throws** on unknown raw values — add a custom
  `init(from:)` (`PlanTier(rawValue:) ?? .unknown`) before decoding real backend docs.
- **Minor / `MealEditSheet`:** prefill formats values (`%.2f` items, `%.1f`/`%.0f` micros),
  so opening + saving untouched can shift stored values by rounding and mark `edited: true`.
  Cosmetic for a personal tool; tighten if it ever matters.

## Verification Commands

Use these after integrating worker patches (iOS lives under `ios/` since 2026-06-12):

```bash
cd ios
xcodegen generate
xcodebuild -project NutritionSnap.xcodeproj -scheme NutritionSnap \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus' \
  -derivedDataPath build build

cd ../functions && npm run build   # backend typecheck
```

Simulator smoke hooks:
```bash
SIMCTL_CHILD_USE_SAMPLE=1 SIMCTL_CHILD_START_TAB=calendar SIMCTL_CHILD_OPEN_DAY=1 \
  xcrun simctl launch booted com.kikman.nutrisnap

SIMCTL_CHILD_AUTO_CAPTURE=1 SIMCTL_CHILD_MOCK_RESULT=happy \
  xcrun simctl launch booted com.kikman.nutrisnap

# Meal-edit regression (M4A): logs a mock meal, edits it through the real save path
# (kcal→800, fiber→9.9), then relaunch + open today to check persistence + rollup.
SIMCTL_CHILD_AUTO_CAPTURE=1 SIMCTL_CHILD_MOCK_RESULT=happy \
SIMCTL_CHILD_AUTO_EDIT=1 SIMCTL_CHILD_AUTO_EDIT_SAVE=1 \
  xcrun simctl launch booted com.kikman.nutrisnap
```
