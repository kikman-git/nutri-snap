import SwiftUI

/// Three-tab shell with a raised center camera (PRD §5.2 — capture is the hero action).
/// Custom bar (not stock `TabView`) so the camera button can sit above the bar. The three
/// screens stay alive in a ZStack so tab switches preserve their state.
///
/// The raised button is contextual: off the Snap tab it switches to it; on the Snap tab it
/// *is the shutter* — it fires the live camera. The library picker on the screen is the
/// secondary path. `RootView` owns the `CaptureViewModel` so the shutter and the screen share it.
struct RootView: View {
    enum Tab: Hashable { case trends, snap, calendar }

    @State private var selection: Tab
    @State private var store: MealStore
    @State private var model: CaptureViewModel
    /// Screenshot hook: force the onboarding gate open (the CLI can't tap through it otherwise).
    private let forceOnboarding: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(store: MealStore? = nil, estimator: MealEstimating? = nil) {
        self.forceOnboarding = ProcessInfo.processInfo.environment["FORCE_ONBOARDING"] != nil
        // Construct the real store/model here (View.init is main-actor) rather than as default
        // arguments, which would be evaluated at nonisolated call sites.
        let env = ProcessInfo.processInfo.environment
        // Screenshot hook: USE_SAMPLE runs the whole app on rich SampleData (no Firestore / no App
        // Check) so the data-dependent Trends + day-diary screens can be driven headlessly.
        _store = State(initialValue: store ?? (env["USE_SAMPLE"] != nil ? .sample : MealStore()))
        // Screenshot hooks (CLAUDE.md): MOCK_RESULT / MOCK_SLOW force the mock estimator so the
        // capture states can be driven headlessly without a live Gemini call.
        let useMock = env["MOCK_RESULT"] != nil || env["MOCK_SLOW"] != nil
        // Production sends the photo to the `scanMeal` Cloud Function (server-side Gemini, with
        // App Check + quota enforced). `ONDEVICE_GEMINI=1` keeps the old direct-to-Gemini path
        // for dev/offline iteration; mock hooks still win for headless screenshots.
        let resolved: MealEstimating
        if let estimator {
            resolved = estimator
        } else if useMock {
            resolved = MockMealEstimator()
        } else if env["ONDEVICE_GEMINI"] != nil {
            resolved = GeminiMealEstimator.shared
        } else {
            resolved = BackendMealEstimator.shared
        }
        _model = State(initialValue: CaptureViewModel(estimator: resolved))
        // Test hook: `START_TAB=trends|calendar` opens straight to a tab (used for screenshots).
        switch env["START_TAB"] {
        case "trends":   _selection = State(initialValue: .trends)
        case "calendar": _selection = State(initialValue: .calendar)
        default:         _selection = State(initialValue: .snap)
        }
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            screen(.trends)   { TrendsScreen() }
            screen(.snap)     { CaptureScreen(model: model) }
            screen(.calendar) { CalendarScreen() }
        }
        .safeAreaInset(edge: .bottom) { tabBar }
        .environment(store)
        // First-run gate (PRD §9 step 5): personalize the target before showing the tabs. Auto-
        // dismisses when onboarding writes the profile (`needsOnboarding` flips false).
        .fullScreenCover(isPresented: Binding(get: { showOnboarding }, set: { _ in })) {
            OnboardingView().environment(store)
        }
        // Run the camera only while the Snap tab is showing; release it elsewhere.
        .task(id: selection) {
            if selection == .snap { await model.camera.start() } else { model.camera.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:                  if selection == .snap { Task { await model.camera.start() } }
            case .inactive, .background:   model.camera.stop()
            @unknown default:              break
            }
        }
    }

    /// Keeps every tab mounted; only the selected one is visible + interactive.
    @ViewBuilder private func screen<V: View>(_ tab: Tab, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
    }

    // MARK: - Custom tab bar

    private var tabBar: some View {
        ZStack {
            HStack(spacing: 0) {
                sideTab(.trends, icon: "chart.bar.xaxis", label: "Trends")
                Spacer(minLength: 96)            // gap the camera button sits in
                sideTab(.calendar, icon: "calendar", label: "Journal")
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                Theme.Palette.surface
                    .shadow(color: Theme.Palette.ink.opacity(0.06), radius: 8, y: -2)
                    .ignoresSafeArea(edges: .bottom)
            )

            cameraButton.offset(y: -18)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)   // don't let the review keyboard lift the bar
    }

    private func sideTab(_ tab: Tab, icon: String, label: String) -> some View {
        Button { selection = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(.caption2))
            }
            .foregroundStyle(selection == tab ? Theme.Palette.accent : Theme.Palette.inkSecondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Show onboarding once the store is ready and the account hasn't personalized its target.
    private var showOnboarding: Bool { forceOnboarding || (store.ready && store.needsOnboarding) }

    private var onSnap: Bool { selection == .snap }

    private var cameraButton: some View {
        Button(action: shutterTapped) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.accent)
                    .frame(width: 64, height: 64)
                    .shadow(color: Theme.Palette.accent.opacity(0.4), radius: 8, y: 3)

                if onSnap && model.phase == .analyzing {
                    ProgressView().tint(Theme.Palette.surface)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.Palette.surface)
                }
            }
            // On the Snap tab, dress it as a shutter (inner + outer ring).
            .overlay {
                if onSnap {
                    Circle().strokeBorder(Theme.Palette.surface.opacity(0.7), lineWidth: 2)
                        .frame(width: 52, height: 52)
                }
            }
            .overlay {
                if onSnap {
                    Circle().strokeBorder(Theme.Palette.background, lineWidth: 3)
                        .frame(width: 72, height: 72)
                }
            }
            .opacity(onSnap && model.phase == .reviewing ? 0.45 : 1)   // review owns the on-screen buttons
        }
        .buttonStyle(.plain)
        .accessibilityLabel(onSnap ? "Take a photo" : "Snap a meal")
    }

    private func shutterTapped() {
        if !onSnap {
            selection = .snap                                   // first bring the viewfinder up
        } else if model.camera.status == .ready,
                  model.phase != .reviewing, model.phase != .analyzing {
            Task { await model.shoot() }                        // on the Snap tab, the button is the shutter
        }
        // No live camera (Simulator) or mid-review → the on-screen buttons / library CTA are the path.
    }
}

#Preview {
    RootView(store: .sample, estimator: MockMealEstimator())
}
