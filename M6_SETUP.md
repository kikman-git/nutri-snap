# M6 Setup & Deploy Runbook — server-enforced paywall

What you need to do to make the new backend live and to stand up the paywall plumbing. Code
already committed on branch `m6-paywall`: the `scanMeal` Cloud Function, locked-down Firestore
rules, and the client wired to call `scanMeal`. **The app can't scan until Part A is done** (the
client now points at the backend). Part B can run in parallel.

Firebase project: `nutri-snap-ded1f` · Functions region: `us-central1` · bundle id `com.kikman.nutrisnap`.

---

## Part A — Deploy the backend (do first; unblocks scanning)

### A1. Enable the Blaze plan
Firebase Console → ⚙️ → **Usage and billing → Details & settings → Modify plan → Blaze**, link a
billing account. (Cloud Functions + the outbound call to Gemini need Blaze; Spark can't do either.)
Then set a **budget alert** (e.g. $10/mo) — cheap insurance. Cost is tiny: Gemini 2.5 Flash is
fractions of a cent per scan, and the free-lifetime + monthly caps bound it.

### A2. Get a Gemini API key
[aistudio.google.com/apikey](https://aistudio.google.com/apikey) → **Create API key** (use the
`nutri-snap-ded1f` project so billing/quota live together). This is the Gemini **Developer API**
key — matches the client's old `.googleAI()` backend. It lives ONLY in the backend, never the app.

### A3. Put the secrets in Secret Manager
```bash
cd functions
firebase functions:secrets:set GEMINI_API_KEY
#   → paste the key from A2

# A long random string; you'll paste the SAME value into RevenueCat in B5.
openssl rand -hex 32           # copy the output
firebase functions:secrets:set REVENUECAT_WEBHOOK_SHARED_SECRET
#   → paste that random string
```
Set these **before** deploying — `scanMeal` and `revenuecatWebhook` are bound to them.

### A4. Deploy functions + rules
```bash
# from the repo root
firebase deploy --only functions,firestore:rules
```
- First deploy enables the needed GCP APIs (Cloud Functions, Cloud Build, Artifact Registry,
  Secret Manager) — accept the prompts; it can take a few minutes.
- **Copy the `revenuecatWebhook` URL** from the deploy output (or Functions dashboard) — you need
  it in B5.
- Deploys three functions: `scanMeal` (the scan path), `healthCheck`, `revenuecatWebhook`.

### A5. Register your App Check token
`scanMeal` has `enforceAppCheck: true`, so the app must send a valid App Check token.
- **Simulator / dev:** run the app, find `[FirebaseAppCheck] … debug token: '…'` in the Xcode
  console, then Firebase Console → **App Check → Apps → NutritionSnap → Manage debug tokens** → add
  it. (Per-install; re-add after a sim erase / new machine. This is the #1 "scan fails" cause.)
- **Real device:** add the **App Attest** capability (App Store track) — then it's automatic.
- Confirm the app is registered under **App Check** and Cloud Functions enforcement is on.

### A6. Test scanning
Run the app (real device preferred). Snap a meal → `scanMeal` → Gemini → logged. First **3 scans
are free (lifetime)**; the 4th returns `resource-exhausted` and currently shows the gentle "You've
used your free scans for now." (the paywall UI lands next coding session). Watch logs:
```bash
firebase functions:log --only scanMeal
```
Dev shortcut: launch with `ONDEVICE_GEMINI=1` to use the old direct-to-Gemini path (no backend),
e.g. `SIMCTL_CHILD_ONDEVICE_GEMINI=1 xcrun simctl launch …`.

---

## Part B — RevenueCat + App Store Connect (for the paywall; can run in parallel)

### B1. App Store Connect — app record + Paid Apps agreement
- ASC → **Apps → +** → New App: bundle id `com.kikman.nutrisnap`, check the name "Nutri Snap" is
  free.
- ASC → **Agreements, Tax, and Banking** → sign the **Paid Apps agreement** + complete tax/banking.
  ⚠️ IAP products can't be tested until this is active (banking can take ~a day).

### B2. App Store Connect — subscription products
ASC → your app → **Subscriptions** → create a **Subscription Group** ("Nutri Snap Premium"), then
two **auto-renewable subscriptions** in it:
- Monthly — id `nutrisnap.premium.monthly`, price ~¥800 tier.
- Annual — id `nutrisnap.premium.annual`, price ~¥5,800 tier.

For **each**, add an **Introductory Offer → Free trial → 7 days** (new subscribers). Fill the
required localized name/description; a review screenshot can come once the paywall exists.

### B3. RevenueCat — project + App Store link
- Create a RevenueCat account → **new Project → add App → App Store**, bundle id
  `com.kikman.nutrisnap`.
- Project Settings → Apple App Store → upload an **App Store Connect In-App Purchase key** so
  RevenueCat can validate receipts + receive ASC notifications.

### B4. RevenueCat — entitlement, products, offering
- **Entitlement:** `premium`.
- **Products:** import `nutrisnap.premium.monthly` + `nutrisnap.premium.annual`; attach both to
  `premium`.
- **Offering** `default` with two packages: Monthly → monthly product, Annual → annual product.
  (The paywall reads this offering.)

### B5. RevenueCat — webhook → our backend
Project Settings → **Integrations → Webhooks → Add**:
- **URL** = the `revenuecatWebhook` URL from A4.
- **Authorization** header value = the SAME random string from A3
  (`REVENUECAT_WEBHOOK_SHARED_SECRET`).

This is what flips `users/{uid}/plan/current` to entitled when someone subscribes (and back on
expiry). Cancellation keeps them entitled until the period actually ends (handled in the webhook).

### B6. RevenueCat — public SDK key + sandbox tester
- Project → **API keys** → copy the **public Apple SDK key** (`appl_…`).
- The app reads the key from the **`REVENUECAT_API_KEY` environment variable** (kept out of this
  public repo). Set it in Xcode → **Edit Scheme → Run → Arguments → Environment Variables**, or for
  the CLI as `SIMCTL_CHILD_REVENUECAT_API_KEY=…`. ⚠️ Env vars don't reach an **archived/TestFlight**
  build — before shipping, bake the key into a git-ignored `Secrets.swift` (the public SDK key is
  publishable, so that's safe; see the `revenuecat-ios` skill).
- A RevenueCat **Test Store** key (`test_…`) works for wiring + paywall testing before ASC products
  are live; switch to the `appl_…` key for real sandbox/production purchases.
- ASC → **Users and Access → Sandbox** → create a sandbox tester Apple ID for purchase testing.

---

## Secret/key cheat-sheet
| Value | Lives in | Used by |
|---|---|---|
| `GEMINI_API_KEY` | Secret Manager (functions) | `scanMeal` → Gemini |
| `REVENUECAT_WEBHOOK_SHARED_SECRET` | Secret Manager **and** RevenueCat webhook header | webhook auth |
| RevenueCat public SDK key (`appl_…`) | app (next session) | RevenueCat client SDK |
| ASC In-App Purchase key | RevenueCat dashboard | receipt validation |
| App Check debug token | Firebase Console → App Check | unblocks `scanMeal` in dev |

## Client paywall — BUILT (this session)
The RevenueCat SDK + custom paywall are **coded** (`SubscriptionStore`, `PaywallView`, gating in
`CaptureViewModel`/`CaptureScreen`, upgrade/manage in `ProfileSettingsSheet`). Details + invariants:
the **`revenuecat-ios`** skill. What's left is purely operational + live verification:
- Do Part A (deploy backend) and Part B (RevenueCat/ASC) above.
- Put your key in `REVENUECAT_API_KEY` (B6). Ensure the dashboard entitlement is **`premium`** and
  the offering is **`default`** (the app's constants).
- Verify on a device with a sandbox tester: 3 free scans → paywall → trial purchase → the webhook
  flips `plan/current` → paid scans work. (Allow a few seconds for the webhook; the app shows
  "activating…" and you tap Analyze again — by design.)
- Before App Store submit: swap the `test_` key for `appl_`, bake it into a git-ignored
  `Secrets.swift`, and add a real **privacy policy URL** (placeholder in `PaywallView`).
