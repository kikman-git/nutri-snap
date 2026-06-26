import SwiftUI

/// Three-tab shell with a raised center camera. Custom bar (not stock `TabView`) so the camera
/// button can sit above it; the three screens stay alive in a ZStack so tab switches preserve state.
///
/// Home-first (Warm Bloom D4): the Snap tab opens to **Today·Home**. The raised FAB is contextual —
/// off Snap it switches there; on Home it opens the viewfinder (`capturing`); in the viewfinder it
/// *is the shutter*. Library is the secondary path. `RootView` owns the `CaptureViewModel` so the
/// shutter and the capture screen share it.
struct RootView: View {
    enum Tab: Hashable { case trends, snap, calendar }

    @State private var selection: Tab
    @State private var store: MealStore
    @State private var model: CaptureViewModel
    /// Snap-tab sub-state: false = Today·Home, true = the capture flow (viewfinder → … → logged).
    @State private var capturing = false
    @State private var showGaps = false
    private let forceOnboarding: Bool
    @State private var forcePaywall: Bool = false
    @State private var breathing = false
    @Environment(\.scenePhase) private var scenePhase

    init(store: MealStore? = nil, estimator: MealEstimating? = nil) {
        let env = ProcessInfo.processInfo.environment
        self.forceOnboarding = env["FORCE_ONBOARDING"] != nil
        _store = State(initialValue: store ?? (env["USE_SAMPLE"] != nil ? .sample : MealStore()))
        let useMock = env["MOCK_RESULT"] != nil || env["MOCK_SLOW"] != nil
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
        _showGaps = State(initialValue: env["OPEN_GAPS"] != nil)
        // Capture screenshot hooks live in CaptureScreen.task, so it must be mounted — open the
        // capture flow at launch when one is present.
        let captureHook = env["AUTO_CAPTURE"] != nil || env["AUTO_CAPTURE_FOOD"] != nil || env["AUTO_REVIEW"] != nil
        _capturing = State(initialValue: captureHook)
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
            screen(.snap)     { snapTab }
            screen(.calendar) { CalendarScreen(onSnap: { goToSnap() }) }
        }
        .safeAreaInset(edge: .bottom) { tabBar }
        .environment(store)
        .environment(SubscriptionStore.shared)
        .task { SubscriptionStore.shared.configure() }
        .fullScreenCover(isPresented: Binding(get: { showOnboarding }, set: { _ in })) {
            OnboardingView().environment(store)
        }
        .sheet(isPresented: $forcePaywall) { PaywallView().environment(SubscriptionStore.shared) }
        .fullScreenCover(isPresented: $showGaps) { FillTheGapsView().environment(store) }
        .task(id: cameraShouldRun) {
            if cameraShouldRun { await model.camera.start() } else { model.camera.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:                  if cameraShouldRun { Task { await model.camera.start() } }
            case .inactive, .background:   model.camera.stop()
            @unknown default:              break
            }
        }
        .onChange(of: selection) { _, tab in if tab != .snap { capturing = false } }
        .onAppear { updateBreathing() }
        .onChange(of: shouldBreathe) { _, _ in updateBreathing() }
    }

    @ViewBuilder private var snapTab: some View {
        if capturing {
            CaptureScreen(model: model, onClose: closeCapture, onOpenGaps: requestGaps)
        } else {
            ScrollView {
                TodayHomeView(onOpenGaps: requestGaps).padding(Theme.Spacing.lg)
            }
        }
    }

    @ViewBuilder private func screen<V: View>(_ tab: Tab, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
    }

    private func goToSnap() { selection = .snap; capturing = false }

    private func closeCapture() { capturing = false; model.reset() }

    /// Fill the Gaps is a Plus feature (D9) — gated. Subscribed → open it; otherwise the paywall.
    /// The `OPEN_GAPS` screenshot hook seeds `showGaps` directly, bypassing the gate.
    private func requestGaps() {
        if SubscriptionStore.shared.isSubscribed { showGaps = true } else { forcePaywall = true }
    }

    // MARK: - Custom tab bar

    private var tabBar: some View {
        ZStack {
            HStack(spacing: 0) {
                sideTab(.trends, label: "Trends")
                Spacer(minLength: 96)
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

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

    private var showOnboarding: Bool { forceOnboarding || (store.ready && store.needsOnboarding) }

    private var onSnap: Bool { selection == .snap }

    /// The live camera runs only while the viewfinder is actually on screen.
    private var cameraShouldRun: Bool { onSnap && capturing }

    /// Breathe on Home (inviting a snap) and on the idle viewfinder — never mid-review / analysis.
    private var shouldBreathe: Bool {
        onSnap && (!capturing || model.phase == .idle) && model.phase != .reviewing && model.phase != .analyzing
    }

    private func updateBreathing() {
        if shouldBreathe {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathing = true }
        } else {
            withAnimation(.easeOut(duration: 0.25)) { breathing = false }
        }
    }

    private var cameraButton: some View {
        Button(action: shutterTapped) {
            ZStack {
                if onSnap && capturing && model.phase == .analyzing {
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
            .background(Circle().fill(Theme.Palette.surface))
            .amberButtonShadow()
            .scaleEffect(breathing ? 1.04 : 1)
            .opacity(onSnap && capturing && model.phase == .reviewing ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(onSnap && capturing ? "Take a photo" : "Snap a meal")
    }

    private func shutterTapped() {
        if !onSnap {
            goToSnap()
        } else if !capturing {
            capturing = true
        } else if model.camera.status == .ready,
                  model.phase != .reviewing, model.phase != .analyzing {
            Task { await model.shoot() }
        }
        // No live camera (Simulator) or mid-review → the on-screen library CTA is the path.
    }
}

#Preview {
    RootView(store: .sample, estimator: MockMealEstimator())
}
