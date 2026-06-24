import SwiftUI
import FirebaseCore
import FirebaseAppCheck
import FirebaseFirestore

@main
struct NutritionSnapApp: App {
    init() {
        #if DEBUG
        // Simulator/dev can't attest (DeviceCheck & App Attest are device-only), so use the
        // debug provider. It mints a token printed to the console — register it once in
        // Firebase Console → App Check → Apps → Manage debug tokens. Production uses the real
        // attestation providers instead.
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #endif
        FirebaseApp.configure()

        // Offline-first persistence (PRD: single store, works offline). On by default on iOS;
        // set explicitly so the intent is clear. Must precede any other Firestore use.
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
