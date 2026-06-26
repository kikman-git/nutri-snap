import SwiftUI

/// First-run gate (PRD §9 step 5). One calm screen: a warm intro, the body-stats form, a live
/// target preview, then "Use this target" to personalize or "Skip for now" to keep the neutral
/// default (gentle, low-friction — it's editable later in Settings). Presented by `RootView`
/// while `store.needsOnboarding`.
struct OnboardingView: View {
    enum Step { case welcome, profile }

    @Environment(MealStore.self) private var store
    @State private var step: Step = .welcome
    @State private var inputs = ProfileInputs()
    @State private var saving = false

    var body: some View {
        Group {
            switch step {
            case .welcome:
                WelcomeView { withAnimation(.easeInOut) { step = .profile } }
            case .profile:
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        header
                        ProfileFieldsView(inputs: $inputs)
                        TargetPreviewCard(target: inputs.target)
                        buttons
                    }
                    .padding(Theme.Spacing.lg)
                }
                .background(Theme.Palette.background.ignoresSafeArea())
            }
        }
        .onAppear { if let p = store.profile { inputs = ProfileInputs(p) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("A gentle place to start")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.ink)
            Text("A few details set your personal target. No pressure — it's a soft guide, not a rule, and you can change it anytime.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
    }

    private var buttons: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button("Use this target", action: useTarget)
                .buttonStyle(.primary)
                .disabled(saving)
            Button("Skip for now") { saving = true; Task { await store.skipOnboarding() } }
                .buttonStyle(.ghost(muted: true))
                .disabled(saving)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private func useTarget() {
        saving = true
        Task {
            await store.saveProfile(sex: inputs.sex, age: inputs.age,
                                    heightCm: inputs.heightCm, weightKg: inputs.weightKg,
                                    activity: inputs.activity, goal: inputs.goal)
        }
    }
}

#Preview {
    OnboardingView().environment(MealStore.sample)
}
