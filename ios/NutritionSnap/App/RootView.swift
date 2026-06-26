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
    /// Screenshot hook: present the paywall on launch (the CLI can't tap Settings → Upgrade or
    /// exhaust the free quota). Pair with `REVENUECAT_API_KEY` to render live offerings.
    @State private var forcePaywall: Bool = false
    @State private var breathing = false
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
        _forcePaywall = State(initialValue: env["FORCE_PAYWALL"] != nil)
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
            screen(.calendar) { CalendarScreen(onSnap: { selection = .snap }) }
        }
        .safeAreaInset(edge: .bottom) { tabBar }
        .environment(store)
        .environment(SubscriptionStore.shared)
        // Configure RevenueCat once on appear — a no-op without an API key (previews / sample /
        // dev without the env var), and runs well before any paywall is presented.
        .task { SubscriptionStore.shared.configure() }
        // First-run gate (PRD §9 step 5): personalize the target before showing the tabs. Auto-
        // dismisses when onboarding writes the profile (`needsOnboarding` flips false).
        .fullScreenCover(isPresented: Binding(get: { showOnboarding }, set: { _ in })) {
            OnboardingView().environment(store)
        }
        // Screenshot hook only (FORCE_PAYWALL): the production trigger is CaptureViewModel.confirm
        // raising the paywall on a quota/entitlement decline, plus the Settings upgrade row.
        .sheet(isPresented: $forcePaywall) { PaywallView().environment(SubscriptionStore.shared) }
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
        .onAppear { updateBreathing() }
        .onChange(of: shouldBreathe) { _, _ in updateBreathing() }
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
                sideTab(.trends, label: "Trends")
                Spacer(minLength: 96)            // gap the camera button sits in
                sideTab(.calendar, label: "Journal")
            }
            .padding(.horizontal, 40)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xs)
            .frame(maxWidth: .infinity)
            .background(
                Theme.Palette.surface
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
                    }
                    .shadow(color: Theme.Shadow.warm.opacity(0.05), radius: 8, y: -3)
                    .ignoresSafeArea(edges: .bottom)
            )

            cameraButton.offset(y: -20)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)   // don't let the review keyboard lift the bar
    }

    /// Custom 1.8-stroke keyline tabs (Trends wave · Journal book) — clay when active,
    /// muted sage-taupe at rest (design §1.1).
    private func sideTab(_ tab: Tab, label: String) -> some View {
        let active = selection == tab
        let color = active ? Theme.Palette.accent : Theme.Palette.tabInactive
        let style = StrokeStyle(lineWidth: active ? 2 : 1.8, lineCap: .round, lineJoin: .round)
        return Button { selection = tab } label: {
            VStack(spacing: 5) {
                Group {
                    switch tab {
                    case .trends:   BrandIcon.Trends().stroke(color, style: style)
                    case .calendar: BrandIcon.Journal().stroke(color, style: style)
                    case .snap:     EmptyView()
                    }
                }
                .frame(width: 25, height: 25)
                Text(label)
                    .font(.custom("HankenGrotesk-SemiBold", size: 10))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Show onboarding once the store is ready and the account hasn't personalized its target.
    private var showOnboarding: Bool { forceOnboarding || (store.ready && store.needsOnboarding) }

    private var onSnap: Bool { selection == .snap }

    /// Breathe only while the viewfinder is idle on Snap — never mid-review / analysis.
    private var shouldBreathe: Bool { onSnap && model.phase == .idle }

    private func updateBreathing() {
        if shouldBreathe {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathing = true }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { breathing = false }
        }
    }

    /// Raised gradient FAB with a 4px surface ring + amber glow (design's center shutter).
    private var cameraButton: some View {
        Button(action: shutterTapped) {
            ZStack {
                if onSnap && model.phase == .analyzing {
                    ProgressView().tint(.white)
                } else {
                    BrandIcon.Camera()
                        .stroke(.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 56, height: 56)
            .background(Circle().fill(Theme.Gradient.primary))
            .padding(4)
            .background(Circle().fill(Theme.Palette.surface))   // 4px surface ring
            .amberButtonShadow()
            .scaleEffect(breathing ? 1.04 : 1)
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
