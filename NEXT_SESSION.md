# NEXT_SESSION.md — Nutrition Snap handoff

The running state + what to do next. `PRD.md` = product truth · `CLAUDE.md` = how to build/run **and the full milestone history** · this file = current state + the next moves.

> **Layout note:** the repo is a multi-platform monorepo — the iOS app lives under **`ios/`**
> (`ios/project.yml`, `ios/NutritionSnap/…`); `functions/`, Firebase config, `design/`,
> `test-assets/`, and docs stay at root; `android/` is a placeholder (PRD: Android is v2+).

## Where we are (2026-06-26)

Milestones **1–5 + 4A done**, and **M6 (server-enforced paywall) is code-complete** — backend + client both built and verified; what's left is operational deploy + a live purchase test. App builds + runs on the iPhone 16 Plus sim (iOS 18.6). See CLAUDE.md for the per-milestone detail.

- **M6 just landed — server-enforced paywall, no login (the whole thing is built).** `scanMeal` Cloud Function is the only path to Gemini (Auth + App Check + quota); RevenueCat drives a custom SwiftUI paywall (client = UX only, server = enforcer). **Open PR: [#2](https://github.com/kikman-git/nutri-snap/pull/2)** (`m6-paywall` → `master`, 5 commits). iOS BUILD SUCCEEDED, backend tsc clean, paywall verified live against the RevenueCat Test Store on the sim. **Next session = operational only** (see ⬇️ "Next session — start here"). Two new skills: `revenuecat-ios`, `nutrisnap-ios`.
- **M5 — onboarding + personalized targets.** First-run gate collects body stats → **Mifflin–St Jeor** daily target (`Models/NutritionMath.swift`); micro references **personalized by sex**; edit later via the person icon in the Trends header. Verified on sim. Hook: `FORCE_ONBOARDING=1` + `USE_SAMPLE=1`.
- **Repo is public / open-source.** Secret audit done: **no API keys or credentials in any tracked file or in git history.** `GoogleService-Info.plist` is gitignored + was never committed; Cloud Functions read every secret from `process.env`; the RevenueCat key is read from `REVENUECAT_API_KEY` (never committed). App Check **debug tokens** were scrubbed from the docs.

## Next session — start here

**All M6 code is done.** The remaining work is operational setup + live verification, then the App Store track. In order:

1. **Deploy the backend** — `M6_SETUP.md` Part A (Blaze → `GEMINI_API_KEY` + webhook secret → `firebase deploy` → register the App Check token). ⚠️ Until this is live the app can't scan (the client calls the backend now). Dev shortcut: `ONDEVICE_GEMINI=1`.
2. **RevenueCat + ASC** — `M6_SETUP.md` Part B (subscriptions + 7-day trials, entitlement `premium`, offering `default`, webhook → the deployed URL with the shared secret).
3. **Set `REVENUECAT_API_KEY`** on the run scheme; **live-verify on a device** w/ a sandbox tester: 3 free scans → paywall → trial purchase → webhook flips `plan/current` → paid scans work. (Allow a few seconds for the webhook; the app shows "activating… tap Analyze again" by design — don't expect instant.)
4. **Pre-submit code follow-ups** (small, gated on shipping): swap the `test_` RevenueCat key for the `appl_` key and **bake it into a git-ignored `Secrets.swift`** (scheme env vars don't reach archived builds — see the `revenuecat-ios` skill); replace the placeholder **privacy-policy URL** in `PaywallView` (`TODO(launch)`).
5. Then the **device + App Store track** below.

Merge PR #2 once the live purchase test passes (or merge now and treat ops as follow-up — your call).

## M6 reference — server-enforced paywall (no login) · branch `m6-paywall` · ✅ built

The locked decisions + what each commit did. (The active to-do is the "start here" list above;
this is the design record.) Decided via design grill (2026-06-26). The "add login" task was reframed: login isn't needed
to take money (StoreKit bills the Apple ID; RevenueCat tracks entitlement against
`appUserID = Firebase anon uid`). So **login is deferred** and the goal — cover infra cost —
is met by a **paywall with a full backend trust boundary**.

**Locked decisions**
- **Identity:** stay anonymous Firebase auth; defer Apple/Google sign-in (revisit when
  cross-device data continuity matters). RevenueCat `appUserID = Firebase uid`.
- **Free taste:** 3 *lifetime* free scans, enforced server-side (reinstall resets it — ok;
  harden with DeviceCheck only if abused).
- **Subscription:** Monthly + Annual, each with a 7-day Apple free trial. Prices set in ASC
  (~¥800 / ~¥5,800 start; infra cost is <$1/user/mo, so margin isn't the constraint).
- **Enforcement:** full backend trust boundary — Gemini moves server-side; the only path to it
  is the authenticated + App-Check-enforced + quota-checked callable.
- **Transport:** inline image bytes in ONE `scanMeal` callable (reserve → Gemini →
  commit/refund, all server-side). **No R2, no Cloud Storage** (skips milestone M7); photos
  stay on-device.
- **Paywall:** custom SwiftUI on the Theme, driven by RevenueCat offerings + a Restore button.
- **Out of scope:** meal_photo only (OCR = v2), no login, no R2/cloud photos, no account-
  deletion UI (flag for launch — PRD Q#11).

This **collapses milestones M5/M6/M8/M9 and drops M7** (see `IMPLEMENTATION_MILESTONES.md` →
"v1 Paywall Scope Decision" + the 2026-06-12 review findings = the scaffold bugs to fix as we go).

**Build order (backend-first) — status 2026-06-26**
1. ✅ **DONE** (commit `16359b7`) — `functions/`: collapsed the R2 multi-call scaffold into one
   `scanMeal(imageBase64, note)`; server-side Gemini via **REST `fetch`** (no new dep; key in
   Secret Manager; ported `GeminiPrompt` + the thinking cap); 3-lifetime free + monthly paid cap;
   `enforceAppCheck: true`; webhook fixed (CANCELLATION→active-until-expiry, header-only secret).
   Typechecks.
2. ✅ **DONE** (commit `16359b7`) — `firestore.rules`: `plan`/`quota`/`scans` backend-write-only,
   client read-only.
3. ✅ **DONE** (commit `eef966a`) — `ios/`: `BackendMealEstimator` calls `scanMeal` via
   FirebaseFunctions; on-device Gemini retired behind `ONDEVICE_GEMINI=1`. Builds + mock smoke OK.
4. ✅ **DONE (this session)** — RevenueCat SDK + paywall, builds clean (RevenueCat 5.80.0):
   - `SubscriptionStore` (`Services/`) — configures RevenueCat, follows Firebase auth so
     `appUserID == uid`, exposes `isSubscribed`/`offering`/purchase/restore/manage. Key from the
     **`REVENUECAT_API_KEY` env var** (`RevenueCatConfig`), not committed (public repo).
   - **Custom SwiftUI paywall** (`Features/Paywall/PaywallView.swift`) on the Theme — Annual+Monthly
     from the `default` offering, 7-day trial copy, Restore, terms/privacy. Entitlement `premium`.
   - **Gating:** `scanMeal` `.quotaReached` → paywall (photo kept); webhook-lag race handled
     ("activating… tap Analyze again", no paywall loop). Upgrade/Manage row in `ProfileSettingsSheet`.
   - **Note:** did *not* wire `PlanService`/`PlanModels` — they're a dead client-quota seam under the
     backend-enforced model. Left untouched. Two new skills: `revenuecat-ios`, `nutrisnap-ios`.
   - ⏳ **Operational only (you):** deploy backend (Part A), RevenueCat/ASC (Part B), set
     `REVENUECAT_API_KEY`, then live-verify on a device w/ sandbox tester. See `M6_SETUP.md`.

**➡️ Operational setup + deploy: [`M6_SETUP.md`](M6_SETUP.md)** (Apple Dev Program is PAID ✅).
⚠️ **The app can't scan until Part A (Blaze + secrets + deploy + App Check token) is done** — the
client now calls the backend. Part B (RevenueCat/ASC) unblocks the paywall.

## Next: device + App Store track

The personalized target (the submission-gating feature) is built. Remaining is mostly device verification + distribution mechanics.

1. **Run on a physical iPhone** (live camera + App Check + Gemini only work on-device). Register that install's App Check debug token (Xcode console → Firebase console).
2. **Verify live** (needs #1's token): onboarding writes the profile to Firestore + persists across relaunch; the gate fires for a genuinely new anon user; capture → log → photo round-trips.
3. **Distribution:** create the App Store Connect app record (check the name "Nutri Snap" is free); switch signing to the paid Developer Program team; add the **App Attest** capability; bump `MARKETING_VERSION` → `1.0.0`; archive (Release) → TestFlight.
4. **Compliance:** privacy policy URL (you send food photos to Google/Gemini + use Firebase); App Privacy questionnaire; export-compliance (`ITSAppUsesNonExemptEncryption=NO`); screenshots (6.9" iPhone) + description + Health & Fitness category + age rating.
5. **Remaining product:** Sign in with Apple (M4 — same uid as the anon account); Cloud Storage photo sync (needs Blaze); OCR-label path (v2).

## Open decisions (PRD §11)

- **Q#1 gentle error copy** — implemented across not-food / low-confidence / offline / failure; revisit wording before launch.
- **Q#2 color thresholds** — live as proposed (under `<85%` / in `85–110%` / over `>110%`).
- **Q#3 onboarding skip vs default** — **RESOLVED:** onboarding is skippable and keeps the neutral default target (gentle, low-friction).

## Quick wins (small, anytime)

- [ ] **Real brand colors** — replace placeholder hex in `ios/NutritionSnap/Resources/Assets.xcassets/*.colorset` (keep `BandIn == Accent`, PRD §7).
- [ ] **"Snack logged" sample label** derives from `capturedAt` hour, so a 16:30 sample dinner reads as "Snack" (cosmetic; `SampleData`).
- [ ] (optional) Dark-mode color variants; humanist custom font in `Theme.Typography`.

## Watch-items

- **The M5 work is uncommitted** on `master` — branch before committing.
- A `DayRollup` / `UserProfile` doc missing newer fields decodes via tolerant `init(from:)` (no crash, sensible defaults) — don't remove those decoders.
- Build fails with phantom "no XCFramework found" → the SwiftPM artifacts under `ios/build/SourcePackages` are stale; `rm -rf ios/build/SourcePackages` (or all of `ios/build`) and rebuild (see CLAUDE.md gotchas).
