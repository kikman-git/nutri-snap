import Foundation

/// Where the RevenueCat **public SDK key** comes from. It is intentionally *not* committed — the
/// repo is public — so we read it from the environment:
///
///   • Xcode: Edit Scheme → Run → Arguments → Environment Variables → `REVENUECAT_API_KEY`.
///   • Simulator/CLI: `SIMCTL_CHILD_REVENUECAT_API_KEY=… xcrun simctl launch …`.
///
/// ⚠️ Scheme env vars do **not** reach an archived / TestFlight / App Store build (those aren't
/// launched by Xcode). Before shipping, bake the key in — e.g. a git-ignored `Secrets.swift`
/// returning it here, or an `.xcconfig` build setting surfaced via Info.plist. RevenueCat's public
/// SDK key is publishable (it's extractable from any shipped app), so baking it in is safe; we keep
/// it out of *this* repo only because the repo is open-source. See `docs/M6_SETUP.md`.
///
/// Today's value is a RevenueCat **Test Store** key (`test_…`), good for wiring + sandbox testing.
/// Production needs the real Apple SDK key (`appl_…`) once the App Store Connect products are live.
enum RevenueCatConfig {
    static var apiKey: String? {
        let value = ProcessInfo.processInfo.environment["REVENUECAT_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }
}
