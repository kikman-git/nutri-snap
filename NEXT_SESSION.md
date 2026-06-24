# NEXT_SESSION.md — Nutrition Snap handoff

The running TODO between sessions. `PRD.md` = product truth · `CLAUDE.md` = how to build/run · this file = what to do next.

> **Layout note (2026-06-12):** the repo is now a multi-platform monorepo — the iOS app
> moved to **`ios/`** (`ios/project.yml`, `ios/NutritionSnap/…`); `functions/`, Firebase
> config, and docs stay at root; `android/` is a placeholder. Paths below predate the move:
> read `NutritionSnap/…` as `ios/NutritionSnap/…`.

## Status (2026-06-06)

### ⭐ Direction evolved + new Trends tab (built & verified on simulator 2026-06-06)
The app pivoted to a **personal micronutrient / longevity tool** (see memory: nutrition-app-direction). Built today:
- **3-tab layout, raised center camera:** **Trends ← Snap → Journal** (Journal = renamed Calendar). `RootView` is now a custom tab bar (not stock `TabView`); `START_TAB` still accepts `calendar`/`trends`.
- **Trends tab** (`Features/Trends/TrendsScreen.swift`): on-device insights — kcal trend chart (Swift Charts, 7/30 toggle), **nutrient sufficiency panel** (focused 8, rolling-avg adequacy vs MHLW reference), days-on-track rhythm strip, observational patterns, computed summary — plus an opt-in **"reflect on my week"** Gemini text call (`GeminiReflector` + `MockReflector` behind the `WeeklyReflecting` seam).
- **Data model:** `Nutrient` enum + `NutrientAmounts` map; `Entry.micros` / `DayLog.microTotals`. Capture prompt + `EstimatedMeal` now request/carry micros, so real photos will return them.
- **Decisions (grill-me):** focused-8 nutrients (protein, fiber, omega-3, vit C, vit A, zinc, iron, magnesium); **"daily data, weekly goals"** (rolling adequacy, never daily pass/fail); MHLW adult-male reference until M5 personalization. Reverses PRD §4 "no micros" + "no RDA tables" (PRD/CLAUDE updated).
- **Still on `SampleData`** (rolling ~35-day deterministic history); real persistence = M3.

**Real food photo → estimate + all 7 micros: VERIFIED end-to-end on simulator (2026-06-06).** 3/3 live trials returned sensible, food-consistent micros (e.g. high vit A from carrot+egg, low omega-3 with no oily fish). Fixed a `MAX_TOKENS` truncation bug first: `gemini-2.5-flash` thinking tokens (~2000) were eating the output budget → JSON cut off → intermittent "Couldn't read that". Fix = `GenerationConfig(maxOutputTokens: 4096, thinkingConfig: ThinkingConfig(thinkingBudget: 256))` in `GeminiMealEstimator` (**don't remove the cap**). App Check re-enabled via debug provider; sim debug token registered in console. Test hook: `SIMCTL_CHILD_AUTO_CAPTURE_FOOD=1` + image at `Documents/test_meal.jpg`.

### ⭐ M3 — Persist + calendar — DONE, verified end-to-end on simulator (2026-06-07)
Captured meals persist through `Services/MealStore.swift` (`@MainActor @Observable`, injected via `.environment`) instead of `SampleData`:
- **Anonymous Firebase Auth** → uid (links to Sign in with Apple at M4, same uid + data). **Firestore offline persistence** (`PersistentCacheSettings` in `NutritionSnapApp`).
- **Model** (PRD §8): `users/{uid}/entries/{id}` + per-day rollup `users/{uid}/days/{yyyy-MM-dd}` (new `DayRollup`). Calendar + Trends read `store.rollups`; day diary loads `store.entries(on:)` on tap — **calendar never queries `entries`.** Rollup maintained on write by an **offline-safe `WriteBatch` + `FieldValue.increment`** (transactions can't run offline).
- **Photos are on-device** (`Services/MealPhoto.swift`: `LocalPhotos` under Application Support + `PhotoCache` + `MealPhoto`; `Entry.photoPath` = local filename, best-effort write). **Cloud Storage now needs the Blaze plan → deferred to M4** (cross-device sync); app stays on free Spark. `SampleData` still backs previews (`MealStore.sample`).
- **Firestore rules committed** (safe — no secrets): `firestore.rules`, `firebase.json` (per-user subtree). No `storage.rules` (Storage unused for now).

**Verified end-to-end (2026-06-07):** capture → "Breakfast logged · ~410 kcal" → cold relaunch persists the recent card (read from Firestore), today's calendar band (rollup), and the photo thumbnail (local file). `Entry` micros + `DayRollup` both round-trip through `Firestore.Encoder`/`data(as:)`. Console is set up: Anonymous auth on, Firestore DB created, rules published. (`gemini-2.5-flash` threw transient HTTP 500 "high demand" twice mid-test — gentle "Couldn't read that" handled it, retried fine.)

⚠️ **One rare unhit edge:** a meal with *all* micros zero writes no `microTotals` key, which `DayRollup`'s synthesized `Codable` would reject (the day would drop from `rollups`). Real Gemini meals always return non-zero micros, so it hasn't bitten — if it ever does, give `DayRollup` a custom decoder defaulting `microTotals` to `.zero`.

**Then on this thread:** per-item micros (model returns whole-meal micros now; push to each item for the edit flow) · onboarding/body-stats to personalize references · device install · wire the Edit sheet (still a no-op).

---

**Milestone 1 (static SwiftUI shell) — DONE.** Builds/runs on iPhone 16 Plus (iOS 18.6); both tabs verified.
- XcodeGen project (`project.yml` → generated `.xcodeproj`), iOS 18 min, Swift 5 mode.
- `Theme` tokens (placeholder hex), pure `Models` + `SampleData`, `Capture` + `Calendar` + `DayDetail` screens, bilingual `Localizable.xcstrings`.

**Milestone 2 (Capture → estimate → render) — flow DONE behind a mock; real Gemini call pending Firebase.** Verified on-simulator across every state (idle · analyzing · logged · low-confidence · not-food · error) via the `AUTO_CAPTURE`/`MOCK_RESULT`/`MOCK_SLOW` hooks.
- `PhotosPicker` capture → `CaptureViewModel` (`@Observable`) calm state machine → auto-logged card with quiet Edit; low-confidence invites "Tap to confirm"; gentle not-food/error states.
- **The seam:** `Services/MealEstimating.swift` (protocol + the §6 `EstimatedMeal`/`EstimatedItem` wire contract + `GeminiPrompt`). `MockMealEstimator` backs it now. The real call is a small drop-in (below).
- Decisions locked: backend = **Gemini Developer API** (free tier, no Blaze); bundle id `com.kikman.nutrisnap`.
- Live-camera viewfinder (AVFoundation) is a later refinement — `PhotosPicker` is the verifiable capture for now.

**Firebase project `nutri-snap-ded1f` (proj # 649910571901):** plist in place at `NutritionSnap/Resources/`; signing team `5N7NUK38D4` (free Apple ID, kikifatto@gmail.com). **Real Gemini call VERIFIED working** (smoke test 2026-06-06): the earlier 403 was just **AI Logic not enabled** — fixed by **AI Logic → Get started → Gemini Developer API** (creates the Gemini key + enables the API server-side; no key in the app). The placeholder test image returned a real Gemini `notFood` response in the prompt's gentle tone.
- **App Check is OFF in the app** (`NutritionSnapApp.swift`, provider commented out) to skip the debug-token dance during dev. Re-enable for production (debug provider on simulator, DeviceCheck/App Attest on device). While off, no debug token needed.
- Still to verify: a **real food photo** → actual estimate (placeholder only proves connectivity); then **device install**.

## Quick wins (small, do anytime)

- [ ] **Fix the "Snack logged" sample label.** The recent-card meal word derives from `capturedAt` hour, so a 16:30 sample dinner reads as "Snack". Either shift sample dinner times to ~19:00 in `SampleData.swift`, or label from the meal factory instead of the hour. (cosmetic)
- [ ] **Real brand colors.** Replace placeholder hex in `NutritionSnap/Resources/Assets.xcassets/*.colorset` (Background, Surface, Ink, InkSecondary, Accent, BandUnder, BandIn, BandOver, BandEmpty). Keep `BandIn == Accent` (PRD §7).
- [x] **Real bundle id** — set to `com.kikman.nutrisnap`.
- [ ] (optional) Dark-mode color variants; humanist custom font in `Theme.Typography`.
- [ ] (optional) Screenshot the day-diary detail (needs a deep-link/test hook like the existing `START_TAB`, since the CLI can't tap).

## Milestone 2 — remaining: wire the real Gemini call (PRD §5.2 / §6)

The UI/flow is done. What's left is replacing `MockMealEstimator` with a real one. Single-user, no auth yet.

**Prerequisite _Phat_ owns (in progress):** create the Firebase project, **Build → AI Logic → Get started → Gemini Developer API** (free tier — no Blaze), register the iOS app with bundle id **`com.kikman.nutrisnap`**, enable **App Check**, download **`GoogleService-Info.plist`** → drop it at `NutritionSnap/Resources/GoogleService-Info.plist` (gitignored — never commit).

**Then the drop-in (≈15 lines + project regen). Verify exact API names against the FirebaseAI version you pull — signatures shift occasionally.**

1. `project.yml` — add the package + link the products, then `xcodegen generate`:
   ```yaml
   packages:
     Firebase:
       url: https://github.com/firebase/firebase-ios-sdk
       from: "11.0.0"            # need a version that ships the `FirebaseAI` product
   # under targets → NutritionSnap:
       dependencies:
         - package: Firebase
           product: FirebaseCore
         - package: Firebase
           product: FirebaseAI
         - package: Firebase
           product: FirebaseAppCheck
   ```

2. `NutritionSnapApp.swift` — configure Firebase + App Check debug provider (simulator can't attest):
   ```swift
   import FirebaseCore
   import FirebaseAppCheck

   init() {
       #if DEBUG
       AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())  // before configure()
       #endif
       FirebaseApp.configure()
   }
   ```
   First run prints an App Check **debug token** to the console → paste it into Firebase console → App Check → Apps → manage debug tokens.

3. New `Services/GeminiMealEstimator.swift` — same protocol, real call, reuses `GeminiPrompt` + the `EstimatedMeal` decode:
   ```swift
   import Foundation
   import FirebaseAI

   final class GeminiMealEstimator: MealEstimating {
       private let model: GenerativeModel
       init() {
           let ai = FirebaseAI.firebaseAI(backend: .googleAI())   // Developer API; .vertexAI() to switch
           model = ai.generativeModel(
               modelName: "gemini-2.5-flash",                      // Flash-class vision tier
               generationConfig: GenerationConfig(responseMIMEType: "application/json"),
               systemInstruction: ModelContent(role: "system", parts: GeminiPrompt.systemInstruction))
       }
       func estimate(imageData: Data) async throws -> EstimatedMeal {
           let image = InlineDataPart(data: imageData, mimeType: "image/jpeg")
           let resp = try await model.generateContent(GeminiPrompt.jsonContract, image)
           guard let text = resp.text, let data = text.data(using: .utf8) else { throw EstimationError.failed }
           return try JSONDecoder().decode(EstimatedMeal.self, from: data)
       }
   }
   ```

4. Inject it (keep Mock for previews/tests). Give `CaptureScreen` an initializer:
   ```swift
   @State private var model: CaptureViewModel
   init(estimator: MealEstimating = GeminiMealEstimator()) {
       _model = State(initialValue: CaptureViewModel(estimator: estimator))
   }
   // #Preview { CaptureScreen(estimator: MockMealEstimator()) }
   ```

**Still to do after the swap:** upload the photo to Cloud Storage (currently in-memory only — fine until milestone 3 persistence); wire the Edit sheet (button is a no-op placeholder); refine gentle copy with PRD Q#1; mind cost (one paid vision call per photo).

## Decisions to resolve (PRD §11)
- [ ] **Q#1 Error/edge handling (v1-critical):** the gentle copy for not-food, low confidence, offline, Gemini failure.
- [ ] **Q#2 Color thresholds:** confirm under `<85%` / in `85–110%` / over `>110%` (currently implemented as the proposed values).
- [ ] **Q#3 Onboarding skip vs default target** (relevant at milestone 5).

## Later milestones (PRD §9)
3. Persist + calendar — Firestore offline persistence; `entries` + the per-day rollup doc (don't query `entries` for the calendar).
4. Firebase Auth (Sign in with Apple) + sync — needs Apple Developer Program ($99/yr).
5. Onboarding + Mifflin–St Jeor target math + color thresholds.

## Housekeeping
- `NutritionSnap.xcodeproj` and `build/` are gitignored (XcodeGen regenerates the project; `build/` is derived data — `rm -rf build/` anytime).
- **Not a git repo yet** — consider `git init` + an initial commit before milestone 2.
