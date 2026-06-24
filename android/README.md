# Nutrition Snap — Android (future)

Placeholder for the Kotlin Android app (PRD: Android is explicitly v2+ — do not build yet).

When it starts, it plugs into the same shared, platform-neutral pieces that live at the repo root:

- **Firebase project `nutri-snap-ded1f`** — same Auth users, same Firestore database
  (`users/{uid}/entries` + `users/{uid}/days` rollups, see PRD §8), same App Check gate.
  Register an Android app in the Firebase console and drop `google-services.json` here
  (gitignored, like the iOS plist).
- **`functions/`** — the trusted backend (scan lifecycle, quota, RevenueCat webhook, R2
  signing). Milestones 5–9 in `IMPLEMENTATION_MILESTONES.md` move scan processing behind it;
  by the time Android exists, the client should talk to these endpoints, not Gemini directly.
- **`firestore.rules`** — per-user subtree rules apply to both clients.
- **`design/`** — brand assets (app icon master SVG). Theme tokens are documented in
  `CLAUDE.md` / PRD §7 and implemented per-platform (iOS: `ios/NutritionSnap/Theme/`).
- **`PRD.md`** — product source of truth, including the §6 estimate contract and §8 data
  model both platforms must share.

Suggested stack when the time comes: Kotlin + Jetpack Compose, same three-tab shell
(Trends ← Snap → Journal), CameraX for capture, Firebase KTX (Auth/Firestore with offline
persistence), reading the same rollup docs the iOS calendar reads.
