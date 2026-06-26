# Nutrition Evidence Base

> **Purpose:** the scientific backing for every nutrition calculation Nutri Snap makes, plus
> the research behind the **glucose-impact signal** (the qualitative GI read). Keep this current
> as the science or the features evolve.
> **Used by:** the server-side scan prompt rubric, the in-app *"estimate, not medical advice"*
> framing, and App Store / APPI compliance backing.
> **Last updated:** 2026-06-26 · **Author:** Phat Nguyen (+ research pass)

## How to read this

Each claim is tagged with an honest **strength of evidence**:

- **[STRONG]** — large prospective cohorts / meta-analyses / well-replicated RCTs.
- **[CONVENTION]** — a defensible default *inside* evidence-based ranges, not a proven optimum.
- **[MECHANISTIC + EMERGING]** — solid biological mechanism, clinical evidence still maturing.

Numbers in the app should be presented as **estimates**, never precise truth — the positioning
("gentle coach") and the science point the same way.

---

## 1. Calorie target — Mifflin–St Jeor  **[STRONG]**

**Claim:** BMR via Mifflin–St Jeor, ×activity ×goal → daily kcal target.
**Where in code:** `ios/NutritionSnap/Models/NutritionMath.swift` (`bmr`, `target`).

- Frankenfield's systematic review found Mifflin–St Jeor the **most accurate** of the major BMR
  equations — within 10% of indirect-calorimetry RMR in more people than Harris-Benedict, Owen,
  or WHO/FAO/UNU, with the narrowest error range.
- A later validation found it essentially **unbiased** (95% CI −26 to +8 kcal/day).

**Honest caveats to surface in-app:**
- Accuracy **drops in obesity** (an obesity-specific equation is sometimes proposed).
- Older adults and non-white populations were **underrepresented** in development/validation.
- → Present the target as a *starting point that we refine*, not a verdict.

**Sources:**
- Frankenfield DC, et al. *Comparison of Predictive Equations for Resting Metabolic Rate in
  Healthy Nonobese and Obese Adults: A Systematic Review.* J Am Diet Assoc. 2005.
  https://www.jandonline.org/article/S0002-8223(05)00149-5/abstract
- Frankenfield DC. *Bias and accuracy of resting metabolic rate equations in non-obese and obese
  adults.* Clin Nutr. 2013. https://pubmed.ncbi.nlm.nih.gov/23631843/

---

## 2. Macro split 20% protein / 50% carbs / 30% fat  **[CONVENTION]**

**Claim:** split the kcal target 20/50/30 into protein/carbs/fat grams (4/4/9 kcal/g).
**Where in code:** `NutritionMath.target`.

This is a reasonable **default**, not an optimum. It sits inside the Institute of Medicine's
evidence-based **Acceptable Macronutrient Distribution Ranges (AMDR)**:

| Macro | AMDR (% of energy) | Our default |
|---|---|---|
| Protein | 10–35% | 20% |
| Carbohydrate | 45–65% | 50% |
| Fat | 20–35% | 30% |

**Implication:** fine to ship as a default; **don't claim precision**. A future "higher-protein"
preference (e.g. 25–30%) stays well within AMDR and is worth offering.

**Source:** Institute of Medicine, *Dietary Reference Intakes* (AMDR).
https://www.ncbi.nlm.nih.gov/books/NBK610333/

---

## 3. Micronutrient references — the focused 12  **[AUTHORITATIVE STANDARD]**

**Claim:** daily reference intakes for protein, fiber, omega-3, vitamin C, vitamin A, zinc, iron,
magnesium, **potassium, vitamin D, vitamin B12, folate**, personalized by sex.
**Where in code:** `NutritionMath.microReferences` (values live there).

Basis: **MHLW — Dietary Reference Intakes for Japanese (2020)**, the Japanese national standard
(locale-fit, since the app is Japan-first). Sex is the main driver (iron, zinc, vitamin A,
magnesium and potassium differ); age-banding is a later refinement. Judged on **rolling-average
adequacy vs reference, never daily pass/fail** (a hard product constraint).

**Warm Bloom D2 expanded the set 8 → 12.** Honest grading of the four additions — MHLW sets two of
them as a firmer **RDA (推奨量)** and two as a softer **Adequate Intake (目安量, AI)**, which we
surface as a "reference," not a verdict:

| Nutrient | MHLW figure (adult) | Type | Note |
|---|---|---|---|
| Potassium | 2500 mg ♂ / 2000 mg ♀ | **AI** (目安量) | A separate, higher "target for prevention" (~3000/2600) exists; we use the AI as the gentler reference. |
| Vitamin D | 8.5 µg (both sexes) | **AI** (目安量) | Commonly runs low; sunlight contributes, so a photo under-reads true status — frame softly. |
| Vitamin B12 | 2.4 µg (both sexes) | **RDA** (推奨量) | Animal-source; relevant to vegetarian/vegan patterns. |
| Folate | 240 µg (both sexes) | **RDA** (推奨量) | Higher needs in pregnancy are out of v1 scope. |

> Note: the per-value table is maintained in code, not re-derived here. If the MHLW DRIs are
> revised, update `NutritionMath.microReferences` and note it here. The `NutrientGuide` in-app
> reference list mirrors these figures.

---

## 4. Glucose-impact signal — the in-app "Energy Read" (qualitative GI read)

The feature: a per-meal **gentle / moderate / quick-rise** classification — *not* a GI number,
*not* a personal prediction. This section is the evidence that shapes both the prompt rubric and
the design decision to stay qualitative.

**Where in code (Warm Bloom D1):** surfaced as `EnergyShape { steady, gentleRise, spike }` =
the gentle / moderate / quick-rise read. It is **model-estimated per meal** (not derived on-device)
and carried through the §6 contract — `EstimatedMeal.energy` (`Services/MealEstimating.swift`) ↔
`EstimatedMealWire.energy` (`functions/src/models.ts`), requested in the scan prompt and
**normalized server-side** to the three allowed values (`functions/src/index.ts`). The prompt
instructs the model to weigh the §4.2 levers below; the output is a wordless cue, never a number.

### 4.1 Why it matters long-term  **[STRONG]**

A mega-cohort meta-analysis (>100,000 participants; Richard Doll Consortium) links **high GI/GL**
to higher incidence of **type-2 diabetes, cardiovascular disease, diabetes-related cancers, and
all-cause mortality**; low GI/GL to reduced risk. A separate meta-analysis of 14 cohorts
(229,213 participants, ~11.5 yr) reported **+13% / +23%** CVD risk for high GI vs GL respectively.

- *Lancet Diabetes & Endocrinol.* 2024 (mega cohorts).
  https://www.thelancet.com/journals/landia/article/PIIS2213-8587(23)00344-3/abstract
- Linus Pauling Institute, *Glycemic Index and Glycemic Load* (overview).
  https://lpi.oregonstate.edu/mic/food-beverages/glycemic-index-glycemic-load

### 4.2 The levers the model should weigh  **[STRONG — RCT-backed]**

These are exactly the cues to encode in the scan rubric (carb type/portion push **up**; the rest
push **down**):

- **Protein & fat blunt the spike** — protein boosts insulin availability, fat slows gastric
  emptying; protein has ~**2–3×** the effect of fat (linear dose-response).
  https://pmc.ncbi.nlm.nih.gov/articles/PMC5525123/
- **Viscous fiber blunts it** — slows gastric emptying / glucose transport (β-glucan, etc.).
- **Food order (veg/protein before carbs)** — the strongest, most *actionable* lever: incremental
  glucose AUC **~73% lower** when vegetables + protein are eaten before carbohydrate; >40% peak
  reduction replicated in prediabetes RCTs.
  - Shukla AP, et al. *Food Order Has a Significant Impact on Postprandial Glucose and Insulin
    Levels.* Diabetes Care. 2015. https://pmc.ncbi.nlm.nih.gov/articles/PMC4876745/
  - Imai S, et al. *Eating vegetables before carbohydrates improves postprandial glucose
    excursions.* 2013. https://pmc.ncbi.nlm.nih.gov/articles/PMC3674531/
- **Acid (vinegar)** — meta-analysis: postprandial glucose **−14.6 mg/dL**, insulin −1.29 mU/L.
  - Shishehbor F, et al. *Vinegar consumption can attenuate postprandial glucose and insulin
    responses.* Diabetes Res Clin Pract. 2017. https://pubmed.ncbi.nlm.nih.gov/28292654/

**Design takeaway:** lead the in-app "lever" copy with **food order / pairing**
("a few bites of veg or protein first steadies it") — strongest evidence, gentlest tone.

### 4.3 Why qualitative, NOT a number  **[STRONG]**

The science actively *forbids* a precise GI figure:

- **Huge variability:** intra-individual CV **~43%** even for plain white bread; reproducibility is
  the most consistent criticism of GI.
  - Matthan NR, et al. *Estimating the reliability of glycemic index values…* Am J Clin Nutr. 2016.
    https://ajcn.nutrition.org/article/S0002-9165(22)04625-1/fulltext
  - *Potential contributions of the methodology to the variability of glycaemic index of foods.*
    https://pmc.ncbi.nlm.nih.gov/articles/PMC7839170/
- **Mixed meals aren't additive:** whether GI even applies to a mixed plate is openly debated — a
  per-item GI lookup misrepresents the meal actually eaten.

### 4.4 Why NOT a personal prediction  **[STRONG]**

The same standardized meal produces **wildly different** glucose responses across people; food
features alone predict worse than models that add microbiome + clinical data. A personal curve
needs a **CGM**, not a photo.

- Zeevi D, et al. *Personalized Nutrition by Prediction of Glycemic Responses.* Cell.
  2015;163:1079–1094 (n=800; 46,898 postprandial responses).
  https://www.cell.com/fulltext/S0092-8674(15)01481-6

> **Conclusion (4.3 + 4.4):** a photo can support a **population-level, qualitative** read
> (gentle/moderate/quick) built from the §4.2 levers — never a precise number, never *your* curve.
> The honest design is the scientifically correct design.

### 4.5 Beauty / skin angle (AGEs)  **[MECHANISTIC + EMERGING]**

Excess glucose cross-links collagen into **advanced glycation end-products (AGEs)** → thinner,
stiffer, less elastic skin; high-sugar / ultra-processed diets raise systemic AGEs. Tight glycemic
control cut glycated-collagen formation ~25% over 4 months. Mechanistically solid; clinical
evidence still maturing — **frame as "supported," not proven** (softer than the §4.1 epidemiology).

- Wang X, et al. *The effects of advanced glycation end-products on skin and potential
  anti-glycation strategies.* Exp Dermatol. 2024.
  https://onlinelibrary.wiley.com/doi/full/10.1111/exd.15065
- *Synthetic and Natural Agents Targeting AGEs for Skin Anti-Aging* (review). 2025.
  https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12024170/

---

## 5. Design & compliance implications

1. **Estimate, not medical advice.** Everything glucose- or calorie-related is a general-wellness
   estimate. Never "manage your diabetes." A quiet disclaimer covers it (PRD open Q#4).
2. **Qualitative over numeric** is the *evidence-honest* choice (§4.3–4.4), not a cop-out.
3. **Lead with the food-order lever** (§4.2) — strongest data, gentlest nudge.
4. **The rice trap (Japan-first):** white rice is high-GI *and* central to the cuisine. Frame as
   "rice + fish + veg = steadier," never "rice = bad," or the app turns preachy and tone-deaf.
5. **Present targets as refinable starting points** (§1 caveats), never verdicts.
