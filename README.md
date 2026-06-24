# Nutrition Snap

Bilingual (JA/EN) "gentle nutrition coach": photograph a meal → Gemini estimates nutrition →
a calm color-coded journal + trends. See `PRD.md` for the product, `CLAUDE.md` for build/run
detail, `IMPLEMENTATION_MILESTONES.md` for the roadmap.

## Layout (multi-platform monorepo)

```
ios/        Swift/SwiftUI app (XcodeGen: ios/project.yml → NutritionSnap.xcodeproj)
android/    future Kotlin app (placeholder — see android/README.md)
functions/  Firebase Cloud Functions backend (TypeScript) — shared by both clients
design/     brand assets (app icon master)
PRD.md · CLAUDE.md · IMPLEMENTATION_MILESTONES.md · NEXT_SESSION.md
firebase.json · firestore.rules   (Firebase project config, shared)
```

## Quick start (iOS)

```bash
cd ios
xcodegen generate
open NutritionSnap.xcodeproj   # ⌘R on an iOS 18 simulator
```

Backend:

```bash
cd functions && npm install && npm run build
```
