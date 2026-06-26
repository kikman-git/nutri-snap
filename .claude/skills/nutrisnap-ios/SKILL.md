---
name: nutrisnap-ios
description: >-
  Nutri Snap's iOS / SwiftUI conventions, build/run mechanics, and review checklist. Use when
  building, running, writing, or reviewing Swift/SwiftUI code under `ios/`. Covers XcodeGen
  build+run, the @Observable/@MainActor + .environment architecture, Theme tokens and the gentle
  anti-MyFitnessPal brand constraint, Firestore offline patterns, headless screenshot env hooks,
  and modern-SwiftUI rules pinned to this app's iOS 18 / Swift 5 targets.
---

# Nutri Snap — iOS / SwiftUI

Native SwiftUI app under `ios/` (monorepo: `functions/` backend + `android/` placeholder at root).
Structure and review dimensions are inspired by Paul Hudson's `swiftui-pro` agent skill — **but
pinned to this project's targets**, which differ (see below). `CLAUDE.md` is the full build/milestone
history; `docs/PRD.md` is product truth; `docs/NEXT_SESSION.md` is current state.

## Targets — read first (these differ from generic SwiftUI skills)

- **Min iOS 18**, **Swift 5 language mode** (`project.yml` → `SWIFT_VERSION: "5.0"`), **iPhone only**.
- ⚠️ Generic SwiftUI guidance (incl. `swiftui-pro`) defaults to **iOS 26 + Swift 6.2 strict
  concurrency**. Do **not** apply that here: no iOS 26-only APIs, and don't introduce Swift 6
  strict-concurrency refactors — we're deliberately in Swift 5 mode until the shell stabilizes
  (CLAUDE.md). Use modern SwiftUI that compiles on iOS 18.

## Build & run (XcodeGen)

- The `.xcodeproj` is **generated** from `ios/project.yml` and is git-ignored — **never hand-edit
  it**. Any new `.swift`/asset under `ios/NutritionSnap/` is picked up on regenerate; no project
  surgery. New SwiftPM packages go in `project.yml` `packages:` + the target `dependencies:`.
- Regenerate: `cd ios && xcodegen generate`
- Headless build (redirect — full logs overflow the scratch dir):
  `xcodebuild -project NutritionSnap.xcodeproj -scheme NutritionSnap -destination 'platform=iOS Simulator,name=iPhone 16 Plus' -derivedDataPath build build > ~/ns_build.log 2>&1` then `grep -E 'error:|BUILD' ~/ns_build.log`.
- Run on sim: `simctl boot` → install the `.app` from `ios/build/Build/Products/Debug-iphonesimulator/` → `simctl launch booted com.kikman.nutrisnap` (**no `-w`** — it waits for a debugger → blank screen).
- **Gotchas:** phantom "no XCFramework found" → stale SwiftPM artifacts, `rm -rf ios/build/SourcePackages` and rebuild. After moving/renaming the repo or derived data → wipe `ios/build/Build` + `ModuleCache.noindex` (PCHs bake absolute paths).

## Architecture & idioms

- **Stores/VMs are `@MainActor @Observable final class`**, injected via `.environment(store)`, read
  via `@Environment(Store.self) private var store`. Examples: `MealStore`, `SubscriptionStore`,
  `CaptureViewModel`. Sheets inherit the presenter's environment.
- **Bindings from a passed-in observable:** shadow it — `@Bindable var model = model` — then use
  `$model.field` (see `CaptureScreen.reviewPanel` and the paywall sheet binding).
- **Seams are protocols** with a mock + a real impl, swapped in `RootView.init` via env hooks
  (`MealEstimating` → `MockMealEstimator` / `GeminiMealEstimator` / `BackendMealEstimator`). Put new
  external dependencies behind a seam so previews/tests/screenshots stay hermetic.
- **Models (`Models/`) stay UIKit/SwiftUI-free** — pure `Codable`. UIKit lives in view models /
  services. The `DayBand → Color` mapping lives in `Theme.swift`, not the model.
- Organize by **feature folder** under `Features/`; one primary type per file.
- **Dormant code:** `Services/PlanService.swift` + `Models/PlanModels.swift` are an obsolete
  client-side quota seam wired to nothing (the backend enforces quota now). Don't extend or revive
  them.

## Theme & brand (hard constraints, not flavor)

- Use `Theme.Palette / Spacing / Radius / Typography` tokens — **never hardcode** hex or sizes.
  Colors are asset-catalog colorsets (placeholder hex for now).
- Positioning: **gentle nutrition coach, the anti-MyFitnessPal** — calm, forgiving, non-judgmental.
  Calendar "over" is warm amber, **never red**. Errors/empty/offline states are kind. When in
  doubt, choose the calmer, lower-friction, less-judgmental option. (Also a micronutrient-longevity
  tool, not just calories — surface more than kcal.)

## Data layer (Firestore, offline-first)

- Single store, offline persistence (`PersistentCacheSettings`). **No SwiftData.**
- Per-day **rollups** maintained with `FieldValue.increment` inside a `WriteBatch` — **not
  transactions** (transactions can't run offline; increments are commutative + merge correctly).
  The calendar reads tiny rollup docs and **never queries `entries`**.
- Decoders use **tolerant `init(from:)`** (`decodeIfPresent` → sensible defaults) so older docs
  don't crash or get silently dropped — don't remove them.
- Photos live **on-device** (Application Support). **Downsample via ImageIO** (≤1600px on
  capture, ≤600px thumbnails, bounded cache) — never fully decode the 12MP original (jetsam OOM).

## Headless / screenshot hooks (the CLI can't tap the camera, picker, keyboard, or purchase)

Pass as `SIMCTL_CHILD_<NAME>=…`. Existing: `START_TAB`, `USE_SAMPLE`, `FORCE_ONBOARDING`,
`AUTO_CAPTURE`, `AUTO_CAPTURE_FOOD`, `AUTO_REVIEW`(+`AUTO_REVIEW_NOTE`), `MOCK_RESULT`, `MOCK_SLOW`,
`AUTO_EDIT`(+`AUTO_EDIT_SAVE`), `OPEN_DAY`, `ONDEVICE_GEMINI`, `REVENUECAT_API_KEY`. **Add a hook
whenever you add UI that must be screenshotted but can't be reached from the CLI.**

## Review checklist (adapted from swiftui-pro's nine dimensions; pinned to iOS 18 / Swift 5)

Report only genuine problems — don't nitpick or invent issues.

1. **Deprecated APIs** — `NavigationStack` not `NavigationView`; two-param `onChange(of:) { old, new in }`
   not the deprecated single-param form; `PhotosPicker`/`.photosPicker`. Only use APIs available ≤ iOS 18.
2. **State / data flow** — `@Observable` + `@State`/`@Bindable`/`@Environment`. Avoid
   `ObservableObject`/`@Published` unless there's a reason. `@ObservationIgnored` for non-UI fields
   (listeners, tasks).
3. **Navigation** — `NavigationStack`; remember sheets inherit the environment (inject stores there).
4. **Accessibility** — Dynamic Type (use `Font.system` text styles, as `Theme.Typography` does);
   `accessibilityLabel` on icon-only buttons; honor Reduce Motion on non-essential animation.
5. **Performance** — `LazyVGrid`/`LazyVStack` for collections; bounded image caches; no full-res decodes.
6. **Concurrency** — `@MainActor` on stores/VMs; don't introduce Swift 6 strict-concurrency churn
   while in Swift 5 mode. `@preconcurrency import` where a framework isn't yet Sendable-annotated.
7. **Swift hygiene** — one primary type per file; feature folders; no dead code wired in.
8. **Design** — HIG + the gentle brand constraints above.
9. **Dependencies** — **no new SwiftPM packages without the user's consent**; keep them behind a seam.

## Related

- **`revenuecat-ios`** skill — the paywall / subscription / entitlement specifics.
- For an exhaustive modern-SwiftUI audit, Paul Hudson's `swiftui-pro` skill is a good external
  reference — just remember to ignore its iOS 26 / Swift 6.2 defaults for this repo.
