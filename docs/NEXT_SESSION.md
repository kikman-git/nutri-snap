# NEXT_SESSION.md — Nutrition Snap handoff

The running state + what to do next. `PRD.md` = product truth · `../CLAUDE.md` = how to build/run **and the full milestone history** · this file = current state + the next moves.

> **Layout note:** the repo is a multi-platform monorepo — the iOS app lives under **`ios/`**
> (`ios/project.yml`, `ios/NutritionSnap/…`); `functions/`, Firebase config, `design/`,
> `test-assets/` stay at root, **docs now live in `docs/`**; `android/` is a placeholder (PRD: Android is v2+).

## Where we are (2026-06-24)

Milestones **1–6 + 4A done** (M6 = server-enforced paywall — built, not yet deployed); app builds + runs on the iPhone 16 Plus sim (iOS 18.6). See `../CLAUDE.md` for the per-milestone detail.

- **M5 just landed — onboarding + personalized targets.** First-run gate collects body stats → **Mifflin–St Jeor** daily target (`Models/NutritionMath.swift`); micro references **personalized by sex**; edit later via the person icon in the Trends header. Verified on sim (math correct; fixed a segmented-`Picker` binding bug). Hook: `FORCE_ONBOARDING=1` + `USE_SAMPLE=1`.
- **Repo is public / open-source.** Secret audit done: **no API keys or credentials in any tracked file or in git history.** `GoogleService-Info.plist` is gitignored + was never committed; Cloud Functions read every secret from `process.env` (nothing hardcoded). App Check **debug tokens** were scrubbed from the docs — if any were ever live, delete them in Firebase console (App Check → Manage debug tokens). Personal email scrubbed from this doc.
- **Direction (2026-06-26) — next build is M6: a server-enforced paywall, *no login* (grill-resolved).** Branch `m6-paywall`. The Apple Developer Program is now **paid** ✅. See the Active section below.
- **UI revamp — "Warm Bloom" — Phase 0 DONE (2026-06-26); Phase 1 is next session.** Phase 0 (the Theme foundation) is built + verified on the sim: vendored Hanken Grotesk + Newsreader-italic fonts (static instances; partial `Info.plist`), exact Warm Bloom colors + 8 new tokens, the 11-step type scale + accent/overline/gradient/shadow helpers, and the shared components (`PrimaryButton`/`Chip`/`WarmCard`/`ConicRing`/`MicroBloom`/`SectionEyebrow`). Build green. A **temp component gallery** sits behind `GALLERY=1` (`RootView` + `Theme/Components/_ComponentGallery.swift`) — **remove it once Phase 1 wires the components into real screens.** Full plan + the per-file Phase-1 map: **[`WARM_BLOOM_REVAMP.md`](WARM_BLOOM_REVAMP.md)** (see the ✅ Status block at the top).
  - **Decisions locked (2026-06-26):** **D4** home-first (Today·Home as the Snap-tab idle; FAB launches camera — will supersede PRD §5.2's capture-first open), **D2** *expand* nutrients (+Potassium, Vit D, B12, Folate → focused-12), **D1** energy read *model-estimated/full* (`EnergyShape` through the contract), **D3** add optional `mealSlot`. D5–D9 at recommended defaults.
  - **Phase 1 data foundation — ✅ DONE (2026-06-26), iOS + functions build green, verified on sim.** `Nutrient` is now the focused-12 (+potassium/vitaminD/b12/folate); new `EnergyShape` + `MealSlot` enums; `Entry` carries optional `energy`/`mealSlot` (back-compat via synthesized optional `Codable`); `EstimatedMeal.energy` + `asEntry` slot-defaulting; `NutritionMath.microReferences` has the 4 MHLW DRIs; the **two-copy §6 contract + both prompts** (`MealEstimating.swift` ↔ `functions/src/{models,index}.ts`, energy normalized server-side); `NUTRITION_EVIDENCE.md` §3/§4, `NutrientGuide`, `SampleData` + `MockMealEstimator` fixtures all updated. Sim shows Trends sufficiency rendering 12 nutrients + the logged card's 11-micro grid (Potassium/Vit D/B12/Folate with units). ⚠️ Live D1/D2 still gated on the **M6 backend deploy** — verified via mock + `npm run build` only.
  - **Phase 1 screen restyles (§1.1–1.8) — ✅ DONE (2026-06-26), iOS build green, verified on sim.** All eight screen-groups wired to the Warm Bloom components + design (imported from claude.ai/design project `7dd99ae1…`, file `Nutri Snap - Warm Bloom.dc.html`): RootView tab bar + gradient FAB w/ keyline icons (`BrandIcons.swift`); Capture states (idle/review w/ **MealSlot chips** + note/analyzing checklist/**Logged hero** = banner + kcal ConicRing + macro legend + **EnergyRibbon** [new component] + **MicroBloom** + gaps nudge/couldn't-read); Calendar circular cells + amber streak banner + month nav + empty state; DayDetail honey summary + energy-tinted timeline + compact micro grid; Trends **ConicRing focused-12 sufficiency grid** + area sparkline + sage rhythm + honey Reflect frame; Paywall MicroBloom emblem + plan cards (RC bindings intact); onboarding/ShareCard token swaps. New: `EnergyShape.tint`, `MealSlot` review override (`asEntry(slot:)`), `EnergyRibbon`/`BrandIcons` components. **The `GALLERY=1` temp gallery is removed.** Paywall plan cards + Reflect prose are code-complete but need a live RevenueCat offering / AI call to screenshot.
  - **Phase 2 viz** (MicroBloom / ConicRing dials / kcal area sparkline) — folded into Phase 1; verified live on the Logged hero, Trends, and Paywall. No separate phase.
  - **Phase 3 new screens — ✅ DONE (2026-06-26), iOS build green, all verified on sim.** Three net-new screens built to the imported design: **Welcome** (`Features/Onboarding/WelcomeView.swift` — value-prop splash w/ a code-drawn spot illustration; **no Sign-in line**, D7; first step of `OnboardingView` → profile form); **Today·Home** (`Features/Home/TodayHomeView.swift` — the D4 home-first Snap-tab idle: nameless greeting [D8], today kcal ConicRing + sage accent line + macro row, today's-meals list w/ energy dots, sage gap teaser → Fill the Gaps); **Fill the Gaps** (`Features/FillGaps/FillTheGapsView.swift` + `Models/NutrientFoods.swift` curated static table — per-shortfall cards w/ 3 everyday-food tiles each; **no reminder CTA**, D9; **Plus-gated**, shown via `fullScreenCover`). **Navigation shift (D4):** `RootView` now opens the Snap tab to Home; a new `capturing` flag flips Home↔the inline capture flow (the tab bar + shared contextual FAB stay visible per the design, so capture is NOT a cover); the FAB is Home→viewfinder→shutter; close-X on the viewfinder + logged banner return Home; camera runs only while `capturing`. Logged hero's gaps nudge is now a tappable row → Fill the Gaps. New hooks: `OPEN_GAPS=1` (+`USE_SAMPLE=1`) opens Fill the Gaps headlessly; capture hooks (`AUTO_CAPTURE`/`AUTO_REVIEW`/`AUTO_CAPTURE_FOOD`) now also set `capturing` so CaptureScreen mounts. ⚠️ **This supersedes PRD §5.2 (capture-first open) — PRD not yet updated.** Comments kept lean per the standing preference.

## Active: M6 — server-enforced paywall (no login) · branch `m6-paywall`

Decided via design grill (2026-06-26). The "add login" task was reframed: login isn't needed
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
5. **Remaining product:** a **qualitative glucose/GI signal** per meal (planned, evidence-backed in [`NUTRITION_EVIDENCE.md`](NUTRITION_EVIDENCE.md) — gentle/moderate/quick, *not* a number; Phase 1 = per-meal chip); Sign in with Apple (M4 — same uid as the anon account); Cloud Storage photo sync (needs Blaze); OCR-label path (v2).

## Open decisions (PRD §11)

- **Q#1 gentle error copy** — implemented across not-food / low-confidence / offline / failure; revisit wording before launch.
- **Q#2 color thresholds** — live as proposed (under `<85%` / in `85–110%` / over `>110%`).
- **Q#3 onboarding skip vs default** — **RESOLVED:** onboarding is skippable and keeps the neutral default target (gentle, low-friction).

## Quick wins (small, anytime)

- [ ] **Real brand colors** — replace placeholder hex in `ios/NutritionSnap/Resources/Assets.xcassets/*.colorset` (keep `BandIn == Accent`, PRD §7).
- [ ] **"Snack logged" sample label** derives from `capturedAt` hour, so a 16:30 sample dinner reads as "Snack" (cosmetic; `SampleData`).
- [ ] (optional) Dark-mode color variants; humanist custom font in `Theme.Typography`.

## Watch-items

- **M5 + M6 are committed/merged** (PRs #1, #2); the live watch-item is now that the **backend isn't deployed** — the app can't scan until `M6_SETUP.md` Part A is done.
- A `DayRollup` / `UserProfile` doc missing newer fields decodes via tolerant `init(from:)` (no crash, sensible defaults) — don't remove those decoders.
- Build fails with phantom "no XCFramework found" → the SwiftPM artifacts under `ios/build/SourcePackages` are stale; `rm -rf ios/build/SourcePackages` (or all of `ios/build`) and rebuild (see CLAUDE.md gotchas).
