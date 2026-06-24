# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

**Milestone 1 — static SwiftUI shell — builds and runs.** Verified on the iPhone 16 Plus simulator (iOS 18.6): both tabs render with theme tokens + fake data (PRD §9, step 1).

**Milestone 2 — Capture → estimate → render — working with the real Gemini call (verified on simulator 2026-06-06).** The full capture loop runs: `PhotosPicker` capture → `CaptureViewModel` (`@Observable`) state machine → auto-logged card, with all gentle states (idle / analyzing / logged / low-confidence / not-food / error). The AI is behind the `MealEstimating` seam — `GeminiMealEstimator` (Firebase AI Logic → Gemini, **Gemini Developer API** backend, project `nutri-snap-ded1f`) in the app; `MockMealEstimator` for previews/tests (and the screenshot hooks). Firebase AI Logic manages the Gemini key server-side — no key in the app. **App Check is ON via the debug provider** (`NutritionSnapApp.swift`, `#if DEBUG` → `AppCheckDebugProviderFactory`). Each install prints its **own** debug token to the Xcode/sim console (`[FirebaseAppCheck] … debug token: '…'`) that must be registered in Firebase console (App Check → Apps → Manage debug tokens). ⚠️ **A `401 "Firebase App Check token is invalid"` (surfaced by `GeminiMealEstimator`'s logging + the DEBUG `failed` card) = that install's token isn't registered — the #1 cause of Gemini failing on a device or a freshly-reset simulator.** Tokens drift: a sim erase / new Mac / new device each needs its token added. (Current sim token `CB1A6368-9B65-40FB-AA53-8236A83B82E8` — **unregistered as of 2026-06-12**, so live Gemini 401s on the sim until it's added; the older `E14169F4-…` / `7B48C708-…` stopped matching after sim resets.) Production uses real DeviceCheck/App Attest automatically. **Real food photo → estimate + all 7 micros VERIFIED end-to-end on simulator (2026-06-06)** via the `AUTO_CAPTURE_FOOD` hook. ⚠️ **Load-bearing:** `gemini-2.5-flash` is a *thinking* model — reasoning tokens share the output budget and were burning ~2000 tokens, truncating the JSON (`MAX_TOKENS`, intermittent failures). Fixed in `GeminiMealEstimator` with `GenerationConfig(maxOutputTokens: 4096, thinkingConfig: ThinkingConfig(thinkingBudget: 256))` — **don't remove the thinking cap.** Remaining: photo upload to Storage (M3), device install. See `NEXT_SESSION.md`.

**Direction evolved (2026-06-06) — micronutrient longevity tool + Trends tab.** The app is now a personal precision-nutrition tool for long-term health/beauty, not just calories. It tracks a **focused 8** — protein, fiber, omega-3, vitamin C, vitamin A, zinc, iron, magnesium — estimated from the photo, judged on **rolling-average adequacy vs reference (MHLW DRI, adult-male default), never daily pass/fail**. Layout is now **3 tabs with a raised center camera: Trends ← Snap → Journal** (Journal = the former Calendar tab; `RootView` is a custom tab bar). Trends (`Features/Trends/TrendsScreen.swift`) = on-device insights (kcal trend via Swift Charts, nutrient sufficiency panel, rhythm, observational patterns) + an opt-in "reflect on my week" Gemini *text* call (`GeminiReflector`, `WeeklyReflecting` seam). Engine: `Models/TrendsAnalysis.swift`; model gained `Nutrient` + `NutrientAmounts` (`Models/NutritionModels.swift`); the capture prompt + `EstimatedMeal` now carry micros. **This reverses the §4 "micronutrients not tracked" decision below + the "no RDA tables" note** (micros use a small MHLW DRI reference table; calorie target stays Mifflin–St Jeor). Built on `SampleData`; real persistence is M3.

**Milestone 3 — Persist + calendar — DONE, verified end-to-end on simulator (2026-06-07).** Single source of truth is `Services/MealStore.swift` (`@MainActor @Observable`, injected via `.environment`): **anonymous Firebase Auth** for the uid (links to Sign in with Apple at M4, same uid + data), **Firestore with offline persistence** (`PersistentCacheSettings` in `NutritionSnapApp`). Data model is PRD §8: `users/{uid}/entries/{id}` + the per-day rollup doc `users/{uid}/days/{yyyy-MM-dd}` (new `DayRollup`) — calendar + Trends read the tiny rollups (`store.rollups`), the day diary loads one day's `entries` on tap (`store.entries(on:)`); **the calendar never queries `entries`.** Rollups are maintained on write via an **offline-safe `WriteBatch` with `FieldValue.increment`** (not a transaction — transactions can't run offline; increments are commutative + merge correctly). **Photos are stored on-device** under Application Support (`Services/MealPhoto.swift`: `LocalPhotos` + `PhotoCache` + `MealPhoto`; `Entry.photoPath` = local filename) — **Cloud Storage now requires the Blaze plan, so it's deferred to M4** (cross-device sync); the app stays on free Spark. `SampleData` still backs all previews (`MealStore.sample`). Firestore rules committed (`firestore.rules` / `firebase.json`; per-user subtree — **safe to commit, no secrets**). **Verified:** capture → log → cold relaunch persists the recent card, today's calendar band, and the local photo thumbnail; the `Entry` micros + `DayRollup` both round-trip through `Firestore.Encoder`/`data(as:)`. Firebase console now has Anonymous auth + a Firestore database + published rules. (`gemini-2.5-flash` threw transient HTTP 500 "high demand" a couple times mid-test — handled by the gentle "Couldn't read that" state, retried fine; not a code issue.) ⚠️ One rare unhit edge: a meal with *all* micros zero writes no `microTotals` key, which `DayRollup`'s synthesized `Codable` would reject — real Gemini meals always return non-zero micros (see `NEXT_SESSION.md`).

**Capture UX reworked + branding (2026-06-07).** Snap is now **live-camera-first**: `Features/Capture/CameraSession.swift` (`@MainActor @Observable`, `AVCaptureSession` + `AVCapturePhotoOutput`; `@preconcurrency import AVFoundation` + `@unchecked Sendable` on the delegate bridge to silence Sendable warnings) drives a real viewfinder via `CameraPreview` (`UIViewRepresentable`). The **raised nav-bar camera button is the shutter** — off the Snap tab it switches there, on it it fires the camera (`CaptureViewModel.shoot()`); it's dimmed/inert during review/analyzing. **No live camera (Simulator / denied / no device) falls back gracefully** to the library `PhotosPicker`, which is otherwise the quiet secondary CTA. Capture now pauses on a **review step** (new `.reviewing` phase): the photo is staged with an optional **note** field (`CaptureViewModel.note`, bound via `@Bindable`) → **Analyze** runs `confirm(into:)`. The note is folded into the Gemini prompt (`GeminiPrompt.userNote`, appended after `jsonContract` with prompt-injection hygiene — context, not instructions); `MealEstimating.estimate(imageData:note:)` carries it (mock ignores it). State machine: idle → reviewing → analyzing → logged · notFood · failed. **App icon** added (`design/AppIcon.svg` master → `AppIcon.appiconset/icon-1024.png`: cream viewfinder ring + clay bowl + sage sprout). **Display name → "Nutri Snap"** (`CFBundleDisplayName`); bundle id `com.kikman.nutrisnap` + product name `NutritionSnap` unchanged (tied to Firebase/App Check). Verified on simulator (camera falls back; review + full review→confirm→logged pipeline work).

**Capture shows full nutrition + delete + Photos save (2026-06-08).** The logged card now renders the **whole** estimate, not just kcal: a macro row (protein/carbs/fat) + the 7 micros in a 2-col grid (`MealNutrition` in `CaptureScreen.swift`); the Snap screen is wrapped in a `ScrollView` so the taller logged card never clips on smaller phones, and the logged state shows the captured shot (capped) above its breakdown. **Remove a meal**: the fresh-log card (quiet trash button) and each Journal tile (`DayDetailView` `MealTile` → tap "⋯" menu) call `MealStore.delete(_:)` — drops the entry doc, undoes the day rollup via `FieldValue.increment(sign: -1)` (or deletes the rollup doc when it was the day's only meal), and removes the on-device photo + cache (offline-safe, mirrors `save`). Meals **snapped in-app are also saved to the user's Photos** (`Services/PhotoLibrary.swift` — add-only `PHPhotoLibrary`, `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription`); library-picked photos already live there, so only camera captures save (`CaptureViewModel.fromCamera`, fired on log). `GeminiMealEstimator` now logs a one-line success summary (item count · kcal · protein · micros dict) at `.debug`. Breakdown verified on simulator via the mock happy path (mock fixtures gained realistic micros); Photos-save + delete need a device / real data + a registered App Check token to exercise live.

**Journal day-detail micros + Trends robustness (2026-06-08).** `DayDetailView` gained a **Micronutrients** card (the 7 non-protein focused nutrients as `MicroBar`s — that day's total vs daily reference, same calm bar as the macros). Trends' early state was misleading — it said "add more *meals*" but the gate is **logged days** (`TrendsAnalysis.minDaysForTrends = 4`, the old inline `>= 4`); it now shows honest progress ("N days logged so far — about M more…"). ⚠️ **Latent data-loss fix:** a `DayRollup` doc missing `microTotals` (a day whose meals were all zero-micro → `rollupDelta` omits the map; or pre-micros M2 data) **failed to decode and the whole day was silently dropped** from the calendar + Trends (a likely "Trends won't fill" cause). `DayRollup` now has a tolerant `init(from:)` (`decodeIfPresent` → `.zero`/0; encode stays synthesized). New **screenshot hooks** (the CLI can't tap): `USE_SAMPLE=1` runs the whole app on `SampleData` (no Firestore/App Check) so Trends + the diary can be driven headlessly; `OPEN_DAY=1` (with `START_TAB=calendar`) pushes today's diary on appear. Both verified via these hooks.

**Memory: image downsampling fixes the jetsam OOM (2026-06-08).** The OS was killing the app for memory. Profiled with `vmmap --summary` / `heap` on the sim: idle ~33MB, but loading **one** 12MP photo (3024×4032 ≈ **49MB decoded**) through capture peaked at **126MB** — and the diary's `PhotoCache` held full-res decodes in an **unbounded** `NSCache`, so browsing many logged days climbed into the GBs → OOM. Fix (`Services/MealPhoto.swift` → `DownsampledImage` via ImageIO `CGImageSourceCreateThumbnailAtIndex`, `…WithTransform` to bake EXIF orientation, never fully decoding the original): every capture/pick decodes at **≤1600px** (camera `PhotoShot`, library `loadAndReview`, the `documentImage` hook), and `PhotoCache` loads **≤600px** thumbnails into a **bounded** cache (`countLimit 80`, `totalCostLimit 32MB`, per-entry cost set). Re-profiled: one photo now peaks **47MB** (was 126MB). The compressed JPEG on disk is unaffected — only the in-memory decode is capped. ⚠️ `PhotoLibrarySaver` now saves the 1600px image (not the 12MP original) — fine for a food log; if full-res-to-Photos is wanted later, save `photo.fileDataRepresentation()` directly (cheap compressed Data, no 49MB decode).

**Milestone 4A meal edit — integrated + verified on simulator (2026-06-11/12) · repo restructured for Android (2026-06-12).** The three delegated worker patches (`IMPLEMENTATION_MILESTONES.md`) are in: **meal edit** (`Features/EditMeal/MealEditSheet.swift` — pencil button on the fresh-log card + Journal tiles; per-item name/portion/kcal/macros/confidence + meal-level micros; saves via `MealStore.update(_:replacing:)`, which applies only the old→new **delta** to the day rollup via `FieldValue.increment`, handles day-moves, and stays offline-safe), a dormant **plan/quota seam** (`Services/PlanService.swift` + `Models/PlanModels.swift` — `InMemoryPlanService`, not yet wired into any UI; backend replaces it at M6/M9), and the **Cloud Functions scaffold** (`functions/` — placeholder callables for scan lifecycle/quota/RevenueCat/R2; `npm run build` passes; trust boundaries are TODOs, see milestones doc). **Verified end-to-end on the sim:** edit sheet prefills → canned correction through the real save path → survives cold relaunch → day rollup updates exactly once (no double-count). New hooks: `AUTO_EDIT=1` (with `AUTO_CAPTURE`) opens the edit sheet on the fresh log; `AUTO_EDIT_SAVE=1` applies a canned correction (kcal→800, name +" (edited)", fiber→9.9) through `MealEditSheet.save()`. **Repo is now a multi-platform monorepo:** the iOS app lives under **`ios/`** (`ios/project.yml`, `ios/NutritionSnap/`); `functions/`, `firebase.json`, `firestore.rules`, `design/`, docs, and **`test-assets/`** (real meal photos for `AUTO_CAPTURE_FOOD`) stay at root; `android/` is a documented placeholder (PRD: Android is v2+). ⚠️ Two operational gotchas: (1) if the build fails with phantom "no XCFramework found" errors, the SwiftPM artifacts under `ios/build/SourcePackages` are corrupted — delete that dir and re-resolve; (2) after moving/renaming the repo or derived data, wipe `ios/build/Build` + `ModuleCache.noindex` (PCHs bake in absolute paths).

`PRD.md` is the product source of truth; if it conflicts with this file, follow the PRD and update this file. **Running TODO / next-session plan: [`NEXT_SESSION.md`](NEXT_SESSION.md).**

**Environment:** Xcode 16.4 + iOS 18.6 simulator runtime installed; macOS 15.4.1; Swift 6 toolchain; Homebrew; XcodeGen. (`xcode-select -p` → `/Applications/Xcode.app/Contents/Developer`.)

### Build & run (XcodeGen)
**Everything iOS lives under `ios/`** (monorepo: `android/` is a future Kotlin app, `functions/` + Firebase config + docs are shared at root). The `.xcodeproj` is **generated** from `ios/project.yml` and is git-ignored — never hand-edit it; edit `project.yml` and regenerate. Sources are folder-based: any new `.swift`/asset under `ios/NutritionSnap/` is picked up on regenerate, no project surgery.

```bash
cd ios
xcodegen generate              # rebuild NutritionSnap.xcodeproj from project.yml
open NutritionSnap.xcodeproj   # then ⌘R in Xcode

# headless build for a simulator (requires full Xcode):
xcodebuild -project NutritionSnap.xcodeproj -scheme NutritionSnap \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus' \
  -derivedDataPath build build
#   ^ run `xcrun simctl list devices available` to see valid simulator names
```
Scheme / target / bundle id: `NutritionSnap` / `NutritionSnap` / `com.kikman.nutrisnap`. Min **iOS 18**, **Swift 5** language mode (`SWIFT_VERSION` in `project.yml`; bump to 6 once the shell is stable). No tests yet.

### Run on a simulator
```bash
xcrun simctl boot 'iPhone 16 Plus'; open -a Simulator        # boot once
APP=ios/build/Build/Products/Debug-iphonesimulator/NutritionSnap.app
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.kikman.nutrisnap         # NO -w: it means wait-for-debugger → blank screen
xcrun simctl io booted screenshot /tmp/ns.png
```
- `RootView` honors a `START_TAB=calendar` env var — pass it as `SIMCTL_CHILD_START_TAB=calendar xcrun simctl launch …` to open straight to the calendar (the CLI can't tap, so this is how to screenshot a non-default tab).
- A full `xcodebuild` log can overflow the harness scratch dir — redirect to a file on disk (`> /Users/<you>/ns_build.log 2>&1`) and `grep error:` / `tail` it.

### Source layout
Repo root: `ios/` (this app) · `android/` (future Kotlin app, placeholder) · `functions/` (Cloud Functions backend, TypeScript — `npm run build` to typecheck) · `design/` (brand assets) · `test-assets/` (real meal photos for the `AUTO_CAPTURE_FOOD` regression hook) · shared `firebase.json` / `firestore.rules` / docs.

Inside `ios/NutritionSnap/`: `App` (entry + `RootView` tab shell) · `Theme` (design tokens) · `Models` (pure `Codable` types + `SampleData`) · `Services` (`MealEstimating` seam + `MockMealEstimator` + the §6 `EstimatedMeal` contract + `GeminiPrompt`) · `Features/Capture` (`CaptureScreen` + `CaptureViewModel` + `CameraSession`/`CameraPreview`) + `Features/Calendar` (screens) + `Features/EditMeal` (`MealEditSheet`) · `Resources` (`Assets.xcassets` color tokens, `Localizable.xcstrings`). Models stay UIKit/SwiftUI-free (UIKit lives in the view model / services); the `DayBand`→color mapping lives in `Theme.swift`.

**Capture screenshot hooks** (mirror `START_TAB`, since the CLI can't tap the picker, the live camera, or the keyboard): `SIMCTL_CHILD_AUTO_CAPTURE=1` stages a placeholder and runs the **full review→confirm** path on appear; `SIMCTL_CHILD_AUTO_REVIEW=1` (+ optional `AUTO_REVIEW_NOTE=…`) stops on the **review** step so it can be screenshotted. `SIMCTL_CHILD_MOCK_RESULT=happy|lowconf|notfood|error|offline` **forces the mock estimator** (`RootView` swaps `GeminiMealEstimator`→`MockMealEstimator` when `MOCK_RESULT`/`MOCK_SLOW` is set) and the outcome; `SIMCTL_CHILD_MOCK_SLOW=1` stretches the mock delay to 6 s so the "analyzing" frame is catchable. `SIMCTL_CHILD_AUTO_CAPTURE_FOOD=1` runs one **real Gemini** analysis (review→confirm) against an image staged at the app's `Documents/test_meal.jpg` — stage one of the fixtures in **`test-assets/`** (real meal photos) via `cp test-assets/IMG_6779.jpeg "$(xcrun simctl get_app_container booted com.kikman.nutrisnap data)/Documents/test_meal.jpg"` — the headless way to regression-test the live vision+micros pipeline (requires this install's App Check debug token to be registered, see above). **Edit-flow hooks:** `SIMCTL_CHILD_AUTO_EDIT=1` (with `AUTO_CAPTURE`) opens the **edit sheet** on the fresh log; add `SIMCTL_CHILD_AUTO_EDIT_SAVE=1` to apply a canned correction (kcal→800, name +" (edited)", fiber→9.9) through the sheet's real save path — relaunch + `START_TAB=calendar OPEN_DAY=1` then verifies persistence and the rollup delta. Note: live camera itself only runs on a physical device; the Simulator always shows the library fallback.

## What this is

Nutrition Snap — a bilingual (Japanese / English) iOS app. Photograph a meal → AI (Gemini) estimates nutrition → a color-coded calendar shows each day vs the user's personal target. Positioning is the **"gentle nutrition coach" (anti-MyFitnessPal)**: calm, non-judgmental awareness, forgiving on accuracy, Japan-first. This positioning is a hard design constraint, not flavor — when in doubt, choose the calmer, lower-friction, less-judgmental option.

## Stack (decided)

- **Client:** native Swift + SwiftUI, iOS-first. Learning iOS is an explicit project goal — prefer idiomatic, current SwiftUI.
- **Backend:** Firebase — Auth (Sign in with Apple), Firestore, Cloud Storage, AI Logic (Vertex AI in Firebase → Gemini).
- **Single data store:** Firestore with offline persistence. **No SwiftData** (deliberate — avoids a second store + migrations).
- **Localization:** iOS String Catalogs (`.xcstrings`). Bilingual JA+EN architected from day one; one language polished first.
- **AI:** Gemini Flash-class vision tier; stronger model reserved only for low-confidence retries. Prompt template lives server-side; App Check guards the key.

## Architecture / load-bearing decisions

Decided in the PRD; not discoverable from code yet, so keep these in mind.

**AI pipeline — two input modes, one pipeline.** One photo → Gemini → a structured items array. Branching prompt: plated/restaurant food → vision *estimation*; packaged food + label → OCR the 栄養成分表示 → near-exact values (OCR path is v2). Contract:
```
items: [ { name, portion, kcal, protein, carbs, fat, confidence } ]
totals: { kcal, protein, carbs, fat }
balanceNote: string
source: "vision" | "ocr"
```
Every photo = one paid vision call (~100–150/user/month) — cost-awareness matters.

**Firestore model** (full detail in PRD §8):
```
users/{uid}                     profile, targets {kcal,protein,carbs,fat}, createdAt
users/{uid}/entries/{entryId}   photoPath, capturedAt, source, edited, items[], totals, balanceNote
users/{uid}/days/{yyyy-MM-dd}   totals, entryCount, band: "under"|"in"|"over"   ← calendar rollup
Storage: users/{uid}/photos/{entryId}.jpg
```
The **per-day rollup doc** is the key performance pattern: the calendar reads one tiny doc per day instead of querying every meal. Maintain it on entry write (client or Cloud Function trigger). Don't make the calendar query `entries`.

**Nutrition math — personalized, locale-agnostic (Mifflin–St Jeor).** No national RDA tables.
- BMR (W=kg, H=cm, A=yrs): men `10W + 6.25H − 5A + 5`; women `10W + 6.25H − 5A − 161`
- TDEE = BMR × activity (sedentary 1.2, light 1.375, moderate 1.55, active 1.725, very active 1.9)
- Goal adjust: maintain ×1.0, lose −15%, gain +10–15%
- Default macro split of target kcal: protein 20% (÷4 g), carbs 50% (÷4 g), fat 30% (÷9 g)

**Calendar fill = discrete buckets, never a gradient.** under `<85%`, in-range `85–110%`, over `>110%` of target (thresholds proposed — see PRD open Q#2). under = soft cool, in-range = warm clay (the hero / on-track color), over = warm amber — **never red**.

## Design system

Anthropic-*inspired* warm-minimal, but its own brand: cream/ivory backgrounds, ONE warm coral/clay accent, slate-ink text, generous whitespace, humanist typeface. The warm clay accent **is** the calendar "on-track" color — same decision. Implement as a `Theme` + Color-asset token layer (concrete hex TBD at build). Illustrations are AI-generated, used sparingly (onboarding, empty states, celebration); users' food photos carry the visual richness elsewhere.

## Design tenets that constrain implementation

- **Auto-log, quiet edit.** Capture result auto-logs as a warm summary card with a *present-but-quiet* Edit affordance — frictionless for the 80%, correctable for the 20%. Low-confidence results *invite* a tap ("Tap to confirm what this was") rather than asserting.
- **Gentle everything.** Errors, not-food photos, offline, AI failures all handled gently (full handling is PRD open Q#1, v1-critical).
- **Bilingual data:** store nutrition as structured numbers + a display name in the user's locale. Cross-language food dedup (canonical food ID) is v2 — don't build it now.

## Build order (milestone sequence — PRD §9)

Each step is a usable milestone; follow this order.
1. Static SwiftUI shell — two tabs (Camera, Calendar), theme tokens, fake data.
2. Capture → Gemini → render — core magic on-screen, single-user, no auth.
3. Persist + calendar — wire calendar + day diary to stored data.
4. Firebase Auth + sync — Sign in with Apple; data to Firestore/Storage.
5. Onboarding + target math — Mifflin–St Jeor + color thresholds.

**v2+ (do not build in v1):** HealthKit sync, home-screen widget, reminders/notifications, OCR-label path, second-language full polish, monetization (freemium cap), social/sharing, Android.
