# WARM_BLOOM_REVAMP.md — UI revamp plan (multi-session)

A screen-by-screen plan to bring the app to the **"Warm Bloom"** design system. This is the
execution plan for the next sessions — nothing here is implemented yet.

**Sources**
- Design project: *Mobile health app design system* on claude.ai/design — id `7dd99ae1-0601-4d8a-8d3a-ad37be6b0e55`.
- Screens: `Nutri Snap - Warm Bloom.dc.html` (14 screens, 3 stages).
- Tokens: `Nutri Snap Design System.dc.html` + that project's `CLAUDE.md`.
- Read-only mirrors saved this session under the scratchpad tool-results dir (`warm-bloom.html`, `design-system.html`).

**Hard constraint (unchanged):** gentle, anti-MyFitnessPal. The design honors this — **never alarm red**;
caution lives in clay/amber. "Feel, then data": lead with the wordless read, numbers stay quiet + tabular.

---

## ✅ Status — Phase 0 DONE (2026-06-26)

**Phase 0 (Foundation) is implemented and verified on the iPhone 16 Plus simulator** (sample data +
a temporary component gallery). What landed:

- **Fonts** — 7 **static** instances sliced from the variable fonts with `fontTools` (Hanken Grotesk
  400/500/600/700/800 + Newsreader-italic 400/500). Static instances chosen because SwiftUI's
  `.fontWeight()` on variable fonts is unreliable; neither family declares a **Reserved Font Name**
  (checked the OFL copyright lines) so the statics keep clean PostScript names (`HankenGrotesk-SemiBold`,
  `Newsreader-Italic`, …). Vendored under `ios/NutritionSnap/Resources/Fonts/` with both `OFL-*.txt`
  licenses; registered via a **partial** `ios/NutritionSnap/Info.plist` (`UIAppFonts` only) + an
  `INFOPLIST_FILE` setting in `project.yml` — `GENERATE_INFOPLIST_FILE: YES` stays on (Xcode merges the
  generated keys into the partial). `project.yml` `sources` now excludes `Info.plist`. Rendering confirmed.
- **Colors** — the 9 colorsets updated to exact Warm Bloom hex + **8 new tokens** (`Sage`, `Honey`,
  `Hairline`, `SageTintBg`, `SageText`, `AmberTintBg`, `GradTop`, `GradBottom`). Light-only.
- **`Theme.swift`** — 11-step Hanken/Newsreader scale (`displayXL`…`accent` + `Typography.numeral()`),
  `Text.accentLine()` / `.overline()` helpers, `Theme.Gradient.primary` / `.honey`, warm-shadow helpers
  (`.warmCardShadow()` / `.amberButtonShadow()` / `.liftedShadow()`), expanded `Radius`, updated `DayBand`
  fill/onFill. **`screenTitle` / `sectionTitle` kept as aliases** so the 8 existing screens still compile.
- **Components** (`Theme/Components/`) — `PrimaryButtonStyle` / `SecondaryButtonStyle` / `GhostButtonStyle`
  (+ `.primary` / `.secondary` / `.ghost(muted:)` `ButtonStyle` extensions), `Chip`
  (sageTint/amberTint/neutral/dark/outline), `WarmCard` (+ `honey:`), `SectionEyebrow`, `ConicRing`,
  `MicroBloom`. (`EnergyRibbon` intentionally **not** built yet — it's now Phase 1/3 work, see D1.)
- **Gallery** — `Theme/Components/_ComponentGallery.swift` behind the **`GALLERY=1`** launch hook
  (TEMP, dev-only — `RootView` has a matching `fullScreenCover`). Used to verify the whole component set
  + type scale on the sim. **Remove the gallery file + the `showGallery` hook in `RootView` once Phase 1
  has wired the components into real screens.**

Build: green (`xcodebuild … BUILD SUCCEEDED`). ⚠️ `MicroBloom` had to pull its petal trig out of the
ViewBuilder into plain helpers — SwiftUI's type-checker times out on math-heavy `GeometryReader` closures;
keep new chart math in functions, not inline.

### Decisions resolved (2026-06-26) — these reshape Phase 1+
- **D4 → Home-first.** Build a **Today·Home** landing as the Snap-tab idle screen; the center FAB launches
  the camera. A real shift from capture-first → **update PRD §5.2** when this lands.
- **D2 → Expand the tracked set** (not relabel). Add **Potassium, Vitamin D, B12, Folate** → the focused set
  grows from 8 to **12**. This is model/AI/backend work, not just UI (see the file map below).
- **D1 → Energy read, model-estimated (full)** (not on-device-derived). New
  `enum EnergyShape { steady, gentleRise, spike }` carried through the §6 contract + scan prompt + server
  validation + evidence doc. A **new nutrition claim** — document its strength-of-evidence honestly.
- **D3 → Add optional `mealSlot`** (Breakfast/Lunch/Dinner/Snack), defaulting from the capture hour.
- **D5–D9** remain at the recommended defaults in the table below (manual-entry deferred, prose Reflect now,
  drop the Welcome "Sign in" line, nameless greeting, Fill-the-gaps without the reminder CTA + Plus-gated).

### Phase 1 starts with a data foundation (because of D1 + D2)
The hero screens (Logged, Trends sufficiency, Today·Home, meal rows) can't be restyled to show the new
nutrients / energy read until the model + contract carry them. Do this **before** the screen restyles, and
remember the **two-copy §6 contract drifts** + **tolerant decoders**:

1. **`Models/NutritionModels.swift`** — add the 4 cases to `enum Nutrient` (+ `displayName` / `unit`:
   potassium mg, vitaminD µg, b12 µg, folate µg). Add `enum EnergyShape` (Codable) + an optional field on
   `Entry` and a `mealSlot: String?` (or an enum) on `Entry`. `NutrientAmounts` is keyed by rawValue so it
   absorbs new nutrients for free, **but** check the `DayRollup` / `Entry` tolerant `init(from:)` still
   defaults missing keys (old docs won't have K/D/B12/folate/energy/slot).
2. **`Models/NutritionMath.swift`** — extend `microReferences(sex:proteinTarget:)` with MHLW DRIs for the 4
   new nutrients (potassium, vitamin D, B12, folate — by sex where they differ).
3. **`Services/MealEstimating.swift`** — extend `EstimatedMeal` (micros already a bag; add `energy`/slot),
   and **`GeminiPrompt.systemInstruction` + `.jsonContract`** to request the 4 micros + the energy shape.
4. **`functions/src/models.ts` + `functions/src/index.ts`** — mirror the contract in `EstimatedMealWire`
   and update the **server-side** prompt + output validation in `scanMeal` (this is the real path at ship;
   `npm run build` to typecheck). Keep the thinking-cap config.
5. **`docs/NUTRITION_EVIDENCE.md`** — add evidence + honest strength-of-evidence for K/D/B12/folate DRIs and
   the energy-read heuristic (read this doc first — it's the rule for touching any calc or the prompt).
6. **`Models/SampleData`** (`MealStore.sample`) — populate the new micros + energy shapes + meal slots so
   previews / the `USE_SAMPLE` screenshots render the new viz headlessly.

⚠️ **Live verification of D1/D2 is gated on the M6 backend deploy** (the scan path is server-side and not yet
deployed — see `M6_SETUP.md`). Until then, verify via the **mock estimator** fixtures + `npm run build`.

---

## 0 · What "Warm Bloom" changes vs. today

The current palette is already in the right family but **not exact**, the type is system default, and there's
**no gradient / sage / Newsreader-accent / soft-shadow** system. The design is a meaningfully richer language.

| Area | Today | Warm Bloom target |
|---|---|---|
| **Type** | System font, 4 tokens | **Hanken Grotesk** (UI/numbers) + **Newsreader italic** (emotional accent, clay only). 11-step scale. |
| **Accent line** | none | Newsreader-italic clay one-liners on nearly every surface ("a gentle start to the day"). Brand signature. |
| **Primary color** | clay `#C56A4E` | clay `#C97B54`; primary CTAs use the **amber gradient** `linear(150°, #F2B880→#E8A87C)`. |
| **Second accent** | none | **Sage** `#8FA585` (steady/positive) + sage-tint chip `#EEF2EA`/`#6E8866`. |
| **Fills** | surface only | + **Honey** `#EBC9A8`, **amber-tint** `#FBF1E6`, **Hairline** `#F0E7D8`. |
| **Shadows** | flat `ink.opacity(0.06)` | **soft warm** browns: card `0 22 44 -34 rgba(120,90,50,.4)`, amber button glow `0 10 22 -8 rgba(232,168,124,.6)`. |
| **Radii** | card 20 / control 14 / chip 10 | card **22–28**, input **18**, tile **12–18**, pill **999** (Capsule). |
| **Calendar bands** | under=sage `#A9C0B8`, in=clay, over=amber `#E0A23D` | under=**pale sage-tint** `#EEF2EA`, in=**clay** `#C97B54`, over=**soft amber** `#E8A87C`. |
| **Charts** | bars + linear progress | conic **sufficiency rings**, **kcal area sparkline**, **micronutrient "bloom" radial**, **energy-read ribbon**. |
| **Buttons** | flat clay capsule | gradient pill (primary) · amber-tint outline (secondary) · ghost text (tertiary). |

### Screen inventory (design → app)

| # | Design screen | Status in app | Phase |
|---|---|---|---|
| 1 | Welcome / first launch | **Not built** (onboarding jumps straight to the profile form) | 3 |
| 2 | Today · home (app open) | **Not built** (no Home surface; app opens to the camera) | 3 |
| 3 | Snap · Capture (viewfinder) | exists — `CaptureScreen` idle/live | 1 |
| 4 | Snap · Review & note | exists — `.reviewing` phase | 1 |
| 5 | Snap · Analyzing | exists — `.analyzing` (plainer) | 1 |
| 6 | Snap · Logged (**hero**) | exists — `RecentLogCard` (much plainer) | 1 + 2 |
| 7 | Fill the gaps | **Not built** | 3 |
| 8 | Snap · Couldn't read it | exists — `.notFood` / `.failed` | 1 |
| 9 | Journal · Month | exists — `CalendarScreen` | 1 |
| 10 | Journal · Empty | exists-ish (no dedicated empty art) | 1 |
| 11 | Journal · Day detail | exists — `DayDetailView` | 1 + 2 |
| 12 | Trends · Insights | exists — `TrendsScreen` | 1 + 2 |
| 13 | Trends · Reflect on the week | partial — `ReflectionSheet` (prose only) | 1 (+ structured = 3) |
| 14 | Paywall · Nutri Snap Plus | exists — `PaywallView` | 1 |

---

## Phase 0 · Foundation — ✅ DONE (2026-06-26, see Status block above)

Land this whole phase before touching screens; it's the single highest-leverage change and most screens
then become mechanical token swaps. *(Sections 0.1–0.5 below are kept for reference; all implemented.)*

### 0.1 Fonts
- Add **Hanken Grotesk** (400/500/600/700/800) + **Newsreader italic** (400/500) `.ttf` to
  `ios/NutritionSnap/Resources/Fonts/`. XcodeGen picks up folder resources on regenerate.
- Register in `ios/project.yml` → target `info` → `UIAppFonts` array (or an `Info.plist`).
- Use `Font.custom(_:size:relativeTo:)` so Dynamic Type still scales.
- Licensing: both are OFL on Google Fonts — vendor the files, don't fetch at runtime.

### 0.2 `Theme.Typography` — rebuild to the 11-step scale
Map the design scale onto Hanken Grotesk (Newsreader only for the accent token):

| Token | Spec (size/weight/tracking/leading) | Use |
|---|---|---|
| `displayXL` | 56 / 800 / -3% / 1.0 | splash wordmark |
| `display` | 38 / 800 / -2% / 1.05 | reflect headline |
| `title` | 28 / 800 / -2% / 1.1 | screen titles, meal name |
| `headline` | 22 / 700 / -1% / 1.2 | section heads |
| `bodyLarge` | 19 / 400 / 1.5 | lead paragraphs |
| `body` | 16 / 400 / 1.55 | default |
| `label` | 14 / 600 / 1.2 | buttons, field labels |
| `caption` | 13 / 500 / 1.3 | timestamps, meta |
| `overline` | 13 / 700 / .22em / UPPERCASE | section eyebrows |
| `accent` | Newsreader italic, **clay** | the one-line feeling text |
| numerals | tabular, 800 | every number (`.monospacedDigit()`) |

Add a `Text.accentLine()` helper (Newsreader italic + clay) and a `Text.overline()` helper.

### 0.3 Colors — update assets + add tokens
Update the 9 existing `.colorset`s to exact hex, **add** the new tokens:

```
Background  #FBF6EE   Surface   #FFFDF9   Ink       #3A3530   InkSecondary #8A8073
Accent(Clay)#C97B54   Sage      #8FA585   Honey     #EBC9A8   Hairline     #F0E7D8
SageTintBg  #EEF2EA   SageText  #6E8866   AmberTintBg #FBF1E6  GradTop #F2B880  GradBottom #E8A87C
BandUnder   #EEF2EA   BandIn    #C97B54   BandOver  #E8A87C   BandEmpty  (track) #EFE2D0
```
- Note shifts: Ink `#2B2722→#3A3530` (warmer), Accent `#C56A4E→#C97B54`, BandOver `#E0A23D→#E8A87C` (softer), BandUnder → pale sage-tint.
- Light mode only (design is light-only v1) — no dark variants needed.
- Re-check `DayBand.onFill`: on `#EEF2EA` under-cells, text should be sage `#6E8866` (design uses it).

### 0.4 Gradient + shadows + radii
- `Theme.Gradient.primary` = `LinearGradient([#F2B880,#E8A87C], topLeading→bottomTrailing)` (≈150°).
- `Theme.Shadow`: `card` (soft brown), `amberButton` (amber glow), `lifted`. Helper `.warmCardShadow()`.
- `Theme.Radius`: `tile 14 · input 18 · card 24 · pill = Capsule()`.

### 0.5 Shared components (new — put in `Theme/Components/`)
These recur across many screens; build once:
- `PrimaryButton` — gradient pill + amber shadow + white label. (Welcome, Review "Read this meal", Logged, Paywall CTA, Fill-gaps, Trends reflect.)
- `SecondaryButton` — amber-tint fill, clay text, hairline border. `GhostButton` — plain clay/muted text.
- `Chip` — variants: sageTint, amberTint, neutral, dark. (chips/tags/meal-slot selector.)
- `WarmCard` — surface + radius 24 + warm card shadow.
- `ConicRing` — kcal ring (Today, Logged) and the small sufficiency dials (Trends). Param: pct, track, fill, center label.
- `MicroBloom` — the petal radial (7 spokes, length ∝ share-of-daily; colors cycle clay/sage/amber/honey).
- `EnergyRibbon` — the wordless sparkline (steady=flat sage / gentle-rise=amber bump / spike=clay peak). **Depends on the Energy Read data decision — see §Decision D1.**
- `SectionEyebrow` — overline label used atop most cards.
- Restyled **bottom nav** + **camera FAB** (gradient, soft amber shadow, `pulseShutter` breathing animation on the FAB when idle on Snap).

---

## Phase 1 · Restyle existing screens (no model change)

Each is a styling pass once Phase 0 lands. Listed with design ref → target file → the concrete changes.

### 1.1 `App/RootView.swift` — tab bar + FAB
- FAB → gradient fill, amber-glow shadow, 4px surface ring, gentle `scale` breathe when idle on Snap.
- Side tabs → custom 1.8-stroke icons (Trends = squiggle line, Journal = book) to match the keyline brand; active = clay, rest = muted `#B8AC99`. (SF Symbols acceptable as a fallback.)
- Bar: surface, top hairline, `ignoresSafeArea(.keyboard)` already correct.

### 1.2 `Features/Capture/CaptureScreen.swift` — screens 3·4·5·6·8
The biggest screen. Phase 1 covers all states; the **Logged hero's bloom + energy ribbon** are Phase 2/3.
- **Viewfinder (3):** dark scrim radial-gradient over the live feed; centered Newsreader line "snap your plate, that's all" + muted subtitle; Camera/Library glass chips.
- **Review (4):** redesign `reviewPanel` → photo card with a "Looks like a full plate" sage badge; **Meal name** field (eyebrow + editable row w/ pencil); **When** meal-slot chip selector (Breakfast/Lunch/Dinner/Snack — *new field, see D3*); **note** field as Newsreader-italic placeholder; `PrimaryButton` "Read this meal".
- **Analyzing (5):** photo in a spinning amber ring; "Reading your plate" + accent line "finding the good stuff…"; **progressive checklist** (Identified foods ✓ / Estimated portions ✓ / Calculating nutrients …) with sage check pills.
- **Logged hero (6):** rebuild `RecentLogCard` to the hero — photo banner w/ "✓ Logged · just now" overline + meal name; kcal **conic ring** + macro legend (clay/sage/clay dots); **energy ribbon** + accent line (Phase 3 data); **MicroBloom** card "share of today" (Phase 2 viz); "Low on … fill the gaps ›" nudge → routes to Fill-the-gaps (Phase 3); Edit / Delete as Secondary/Ghost buttons.
- **Couldn't read it (8):** the warm "covered bowl" spot illustration (filled shapes + light stroke); title + clay accent line; `PrimaryButton` "Retake photo" + `SecondaryButton` "Enter it manually" (manual entry = D5).

### 1.3 `Features/Calendar/CalendarScreen.swift` — screens 9·10
- Month header + ‹ › circular buttons.
- **Streak banner** — honey-gradient card: "14 days in range this month" + accent line "a calm, even rhythm".
- Day grid → **circular** cells (not rounded squares); today = clay ring outline; future days = muted, no fill; legend dots **under / in range / over** with the new band colors.
- **Empty (10):** open-journal spot illustration + "Your journal starts here" + accent line + `PrimaryButton` "Snap a meal". Replace the current bare empty state.

### 1.4 `Features/Calendar/DayDetailView.swift` — screen 11
- Summary → **honey-gradient** card: big tabular kcal, "of N kcal · in range", accent line, thin progress bar, macro line.
- "The day" **timeline** — vertical connector line + 32px circular meal markers (photo or emoji), each meal in a surface row; current rows already have the data.
- Micros card → keep `MicroBar`s but restyle (track `#EFE2D0`, fill sage when ≥ good else amber). **Label set = D2.**

### 1.5 `Features/Trends/TrendsScreen.swift` — screen 12 (+ Phase 2 rings)
- Header eyebrow "Trends" + "Last N days" + profile circle button.
- **Sufficiency** → 4-col grid of small **ConicRings** (number in center, nutrient label under), sage ≥ good / amber below. Replaces the current `ProgressView` rows. **Set = D2.**
- **Daily calories** → **area sparkline** (gradient fill under the line, dashed target rule, clay dot on best day) replacing the bar `Chart`. Keep Swift Charts.
- **Rhythm** → "11 of 14 days on track" + accent line + row of rounded bars (sage = on track, pale sage = off).
- Reflect → `PrimaryButton` with a leaf/spark icon.

### 1.6 Reflect sheet — screen 13 (`ReflectionSheet` in TrendsScreen.swift)
- Full-screen takeover, honey→canvas top gradient, ✕ close.
- Eyebrow "Your week · dates" → `display` headline → clay accent line → **highlight cards** (icon circle + title + sub).
- Phase 1 can render the existing **prose** string inside this frame; the **structured highlights** layout needs a structured return → **D6**.

### 1.7 `Features/Paywall/PaywallView.swift` — screen 14
- **MicroBloom emblem** at top (reuse the component, static).
- Eyebrow "Nutri Snap Plus" → title "See the full picture of every meal" → accent line.
- Benefit rows w/ sage check circles.
- **Plan cards:** Yearly (clay 2px border + "Best value · save 50%" badge) vs Monthly; tap-to-select; `PrimaryButton` "Start 7-day free trial"; Restore · Terms · Privacy row. Keep RevenueCat package binding; this is layout only.

### 1.8 Onboarding / Profile / Settings / Edit / Share — restyle
- `OnboardingView`, `ProfileForm`, `ProfileSettingsSheet`, `MealEditSheet`, `ShareCard`, `NutrientGuideView`: mechanical token swaps (fonts, gradient on primary CTA, warm cards/shadows, `TargetPreviewCard` → honey gradient + tabular numerals, accent lines where the design implies them). `ShareCard` uses fixed `.system(size:)` fonts → switch to fixed-size `Font.custom("HankenGrotesk-…")`.

---

## Phase 2 · New visualizations (no data-model change; data already exists)

- **MicroBloom radial** — petal length ∝ `micros[n] / references[n]`, capped ~100%. Used on the Logged hero + Paywall emblem.
- **ConicRing sufficiency dials** — Trends grid + kcal rings; from `TrendsAnalysis.sufficiency` and target.
- **kcal area sparkline** — from `store.rollups`; Swift Charts `AreaMark` + `LineMark` + dashed `RuleMark` at target.

These need **no** model/prompt/backend change — only the chosen nutrient label set (D2).

---

## Phase 3 · New screens & features (need a decision and/or model · AI · backend work)

Ordered by cost. Each maps to a design screen the app doesn't have yet.

### 3.1 Welcome / first-launch (screen 1) — *small, but a decision*
- Splash: spot illustration, wordmark, accent line "a calmer way to eat — snap, and we'll read the rest", `PrimaryButton` "Get started" → onboarding.
- **D7:** the design shows "Already have an account? **Sign in**". The app is **anonymous, no login** (locked decision, SIWA is v2+). **Recommend:** ship the value-prop splash only; **drop the Sign-in line** for v1.

### 3.2 Today · Home (screen 2) — *largest navigation change*
A new landing surface: date eyebrow + greeting, **today kcal conic ring** + accent line + macro line, "Today's meals" list (energy-dot + kcal), and a **gap teaser** card ("A little low on magnesium today · 2 ideas ›").
- **D4 (navigation):** the design opens here, with Snap as the center **FAB**, not a tab. Today the app *opens to the live camera* (capture-first, PRD §5.2 tenet). Options:
  - **(a, recommended)** Make **Home the Snap-tab idle screen**: app opens to Home; the FAB launches the camera/capture as a push/sheet. Keeps the 3-zone bar; matches the design; a real shift from capture-first to home-first → **confirm against PRD §5.2**.
  - (b) Add a literal 4th tab (breaks the 3-zone bar).
  - (c) Keep capture-first; fold the today-ring/meals/gap-teaser onto another surface.
- Greeting "Good morning, Ama" implies a **user name** — `UserProfile` has none. **D8:** greet without a name ("Good morning") or add an optional name field in onboarding. Recommend: nameless greeting for v1.
- Data: today's entries + rollup already available via `store`.

### 3.3 Energy Read (cross-cutting concept) — *model + AI + contract*
The steady / gentle-rise / spike-and-dip ribbon is **not in the data model** and appears on Today rows, the
Logged hero, meal cards, and the day timeline. To make it real:
- Add `enum EnergyShape { steady, gentleRise, spike }` + a field on `EstimatedMeal`/`Entry`.
- Extend the **scan prompt** + the §6 contract (`Services/MealEstimating.swift` `EstimatedMeal` ↔ `functions/src/models.ts` `EstimatedMealWire`) to carry it; validate server-side.
- Document the heuristic in `docs/NUTRITION_EVIDENCE.md` (glycemic-load-ish, honest strength-of-evidence) — this is a **new nutrition claim**, treat it carefully.
- **D1:** build Energy Read for real, **or** treat the ribbon as decorative-from-macros (e.g., derive a rough shape from carb:fiber:fat ratio on-device, no prompt change), **or** defer it and ship those surfaces without the ribbon. Recommend: **derive on-device from existing macros** for v1 (no backend/cost change), upgrade to model-estimated later.

### 3.4 Fill the Gaps (screen 7) — *new feature + a dependency*
Per-shortfall nutrient cards (Mg, fiber, …) each with 3 everyday-food suggestion tiles (emoji + "+X%"), plus a
tip and "Add a reminder for tonight".
- Needs a **curated static table**: nutrient → top everyday foods → typical contribution. (No new API; ship as bundled data — keep it evidence-light + honest.)
- Reached from the Logged "fill the gaps ›" nudge and the Today gap teaser.
- **D9:** "Add a reminder for tonight" needs **local notifications**, which are **v2+** in CLAUDE.md. Recommend: ship suggestions **without** the reminder CTA in v1 (or make it a gentle, dismissible "remind me" that we wire to notifications later).
- Gating: design tags this ★ and lists "Fill the gaps" as a **Plus** benefit on the paywall → it's **premium**. Wire behind entitlement.

### 3.5 Structured weekly Reflect (screen 13 highlights) — *seam change*
The design's reflect shows **structured highlight cards** ("11 steady days", "Protein & B12 looked great",
"One gentle nudge: Vitamin D"), not just prose. The seam returns a plain `String`.
- **D6:** either keep prose inside the new frame (Phase 1, cheap) **or** change `WeeklyReflecting.reflect` to return a small struct (headline + accent + `[Highlight]`) and update `GeminiReflector` prompt to emit JSON. Recommend: Phase 1 prose now; structured later if it tests well.

---

## Open decisions

**Resolved 2026-06-26** (see the Status block at the top): **D1** → energy read *model-estimated (full)* ·
**D2** → *expand* the tracked set (+K/D/B12/folate) · **D3** → *add* optional `mealSlot` · **D4** → *home-first*
(Today·Home as the Snap-tab idle, FAB launches camera). **D5–D9** stay at the recommended defaults below.

| # | Decision | Recommendation |
|---|---|---|
| **D1** | Energy Read: real (model+AI) / derived on-device / defer | **Derive on-device from macros** for v1 |
| **D2** | Nutrient set — design shows **Potassium, Vit D, B12, Folate** which the app doesn't track; app tracks omega-3 + Vit A which the design panels vary on. Expand the tracked set, or relabel design charts to the existing focused-8? | **Relabel to the existing 8** for the revamp; treat "track K/D/B12/folate" as a separate product expansion (model + prompt + DRI refs + evidence doc) |
| **D3** | Review adds a **meal-slot** (B/L/D/Snack) selector — new `Entry` field? | Add `mealSlot` (optional, defaults from capture hour as today's `mealWord` does) |
| **D4** | Navigation: Home-first (Snap = FAB) vs capture-first (today) | **(a) Home as Snap-tab idle**, FAB launches camera — confirm vs PRD §5.2 |
| **D5** | "Enter it manually" on not-food — build manual entry now? | Reuse `MealEditSheet` seeded empty; or defer (keep button → retake) |
| **D6** | Reflect: prose vs structured highlights | Prose in the new frame now; structured later |
| **D7** | Welcome "Sign in" line vs no-login | **Drop Sign-in** for v1 (anonymous; SIWA is v2+) |
| **D8** | Greeting name — `UserProfile` has none | Nameless greeting for v1 |
| **D9** | Fill-the-gaps reminder CTA (needs notifications = v2+) | Ship suggestions without the reminder CTA in v1; Plus-gated feature |

---

## Suggested sequencing

1. **Phase 0** (fonts → type scale → colors → gradient/shadow/radii → shared components). One PR; verify on sim with `USE_SAMPLE=1` across a couple screens.
2. **Phase 1** screen-by-screen, leaning on the components. Group: Capture states → Journal/Day → Trends/Reflect → Paywall → Onboarding/Settings/Edit/Share. Use the headless hooks (`MOCK_RESULT=…`, `AUTO_REVIEW`, `AUTO_CAPTURE`, `START_TAB`, `OPEN_DAY`, `FORCE_ONBOARDING`, `FORCE_PAYWALL`) to screenshot each state.
3. **Phase 2** viz components folded into Logged / Trends / Paywall.
4. **Phase 3** by decision order: Welcome (D7) → Today Home (D4/D8) → Energy Read (D1) → Fill the Gaps (D9) → structured Reflect (D6).

**Build/run + conventions:** see `../CLAUDE.md` (XcodeGen — edit `ios/project.yml`, regenerate; never hand-edit
the `.xcodeproj`) and the `nutrisnap-ios` skill. Models stay UIKit/SwiftUI-free. New user-facing strings go in
`Localizable.xcstrings` (bilingual JA+EN architected). Don't touch the paywall trust boundary while restyling —
see the `revenuecat-ios` skill.
