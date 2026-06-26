---
name: revenuecat-ios
description: >-
  Nutri Snap's RevenueCat + paywall integration — the load-bearing invariants and gotchas. Use
  when touching subscriptions, the paywall, entitlement, quota, purchase/restore, the RevenueCat
  webhook, or `scanMeal` gating in this app. Covers the appUserID=Firebase-uid rule, the
  server-as-enforcer trust boundary, the env-only API key, the webhook-lag race, and where each
  piece lives.
---

# RevenueCat + paywall (Nutri Snap)

How this app monetizes: a **server-enforced paywall, no login**. Anonymous Firebase auth + a
RevenueCat subscription billed to the Apple ID. 3 lifetime free scans, then Monthly/Annual (7-day
trial). Decided via design grill 2026-06-26 (see `docs/NEXT_SESSION.md` → "Active: M6").

## The five invariants (don't regress these)

1. **`appUserID` MUST equal the Firebase uid.** The RevenueCat webhook keys entitlement on
   `app_user_id`; the backend reads `users/{uid}/plan/current` per-uid. If the two identities
   diverge, a purchase never reaches the right account. `SubscriptionStore.configure()` adds a
   Firebase `addStateDidChangeListener` → `Purchases.shared.logIn(uid)`. Never call `configure`
   with a hardcoded/anonymous appUserID and forget the `logIn`.

2. **The server is the only enforcer. The client RevenueCat state is UX-only.** `scanMeal`
   (the *only* path to Gemini) checks quota + entitlement against `users/{uid}/plan/current`
   (written **only** by the webhook; client is read-only per `firestore.rules`). A tampered client
   that flips `isSubscribed` gains nothing. So: never gate a scan purely client-side, and never
   trust a client-sent entitlement on the server. The paywall is presented *reactively* when
   `scanMeal` returns `resource-exhausted`/`permission-denied`.

3. **Entitlement id `premium`, offering `default`** — constants in `SubscriptionStore`. They MUST
   match the RevenueCat dashboard exactly. Changing one means changing both the dashboard and the
   constant.

4. **API key comes from the environment only** (`RevenueCatConfig.apiKey` →
   `REVENUECAT_API_KEY`). The repo is public, so the key is never committed. ⚠️ Scheme env vars do
   **not** reach archived/TestFlight/App Store builds — before shipping, bake the key in (a
   git-ignored `Secrets.swift`, or an `.xcconfig` build setting surfaced via Info.plist). The
   RevenueCat *public* SDK key is publishable, so baking it in is safe. Today's key is a **Test
   Store** key (`test_…`); production needs the **Apple** key (`appl_…`).

5. **Webhook lag is real — never loop the paywall.** After a purchase, the client knows instantly
   (`customerInfo`), but the backend's `plan/current` mirror updates **asynchronously** via the
   webhook (seconds). Until it lands, the user is still `tier:free` server-side → an immediate
   re-scan hits the free limit again. `CaptureViewModel.confirm` handles this: on `.quotaReached`,
   if `SubscriptionStore.shared.isSubscribed` is already true, show "activating… tap Analyze again"
   instead of re-presenting the paywall. **Don't auto-retry the scan right after purchase.**

## Where things live

| Concern | File |
|---|---|
| RevenueCat wrapper (configure, logIn, offerings, purchase/restore, manage) | `ios/NutritionSnap/Services/SubscriptionStore.swift` |
| API key from env | `ios/NutritionSnap/Services/RevenueCatConfig.swift` |
| Custom paywall UI + `PremiumStatusRow` | `ios/NutritionSnap/Features/Paywall/PaywallView.swift` |
| Reactive gating (`.quotaReached` → paywall) | `ios/NutritionSnap/Features/Capture/CaptureViewModel.swift` (`showPaywall`) + `CaptureScreen.swift` (sheet) |
| Free-scan count surfaced from the scan response | `ios/NutritionSnap/Services/BackendMealEstimator.swift` → `noteRemainingFreeScans` |
| App-wide configure + inject | `ios/NutritionSnap/App/RootView.swift` (`.task { SubscriptionStore.shared.configure() }`, `.environment(...)`) |
| Settings upgrade/manage entry | `ios/NutritionSnap/Features/Settings/ProfileSettingsSheet.swift` |
| Server enforcement + webhook → `plan/current` | `functions/src/index.ts` (`scanMeal`, `revenuecatWebhook`) |
| Backend-owned docs, client read-only | `firestore.rules` (`plan`/`quota`/`scans` write:false) |
| SPM package | `ios/project.yml` (`RevenueCat` from `purchases-ios-spm.git`, **`RevenueCat` product only**) |

Dead code: `Services/PlanService.swift` + `Models/PlanModels.swift` (`InMemoryPlanService`,
client-side reservation/quota machinery) predate the backend-enforced model and are wired to
nothing. Don't extend them or wire them to RevenueCat — the backend owns reservations/quota now.

## Conventions / API

- **Custom SwiftUI paywall**, not RevenueCatUI (brand: calm, anti-MyFitnessPal). Take only the
  `RevenueCat` SPM product, not `RevenueCatUI`. No countdowns/dark patterns.
- Modern SDK surface: `Configuration.Builder(withAPIKey:).build()`, `customerInfoStream`
  (`for await`), `async` `purchase(package:)` / `restorePurchases()`, `showManageSubscriptions()`
  for cancel/change (we don't ship Customer Center — `showManageSubscriptions` covers Apple's
  required manage path; Restore lives on the paywall).
- Entitlement check: `customerInfo.entitlements.active["premium"]?.isActive == true`.
- Paywall reads `offering.annual` / `offering.monthly` (annual first = best value), falls back to
  `availablePackages`. Trial copy keys off `storeProduct.introductoryDiscount?.paymentMode ==
  .freeTrial`. Savings % computed from monthly×12 vs annual price.
- `SubscriptionStore` is `@MainActor @Observable`, a `.shared` singleton injected via
  `.environment`. `configure()` is idempotent and a **no-op without an API key** (previews/sample
  still run; the paywall shows a calm "couldn't load plans" state).

## Operational setup

Account/ASC steps (Blaze, Gemini key + webhook secret, ASC subscriptions + 7-day trials,
RevenueCat project/entitlement/offering/webhook) are in **`docs/M6_SETUP.md`**. The webhook URL comes
from `firebase deploy`; the shared secret must match Secret Manager's `REVENUECAT_WEBHOOK_SHARED_SECRET`.

## Testing

- Sim/dev: set `REVENUECAT_API_KEY` on the run scheme (or `SIMCTL_CHILD_REVENUECAT_API_KEY=…`).
  Live purchases need a **sandbox tester** Apple ID (ASC → Users and Access → Sandbox) on a device.
- Without the key, the app runs normally and the paywall shows its unavailable state — fine for
  unrelated work.
- Free→paid path needs the backend deployed (`docs/M6_SETUP.md` Part A) + a registered App Check token,
  since `scanMeal` is the gate. `ONDEVICE_GEMINI=1` bypasses the backend for capture-only dev.
