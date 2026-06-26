import SwiftUI

/// Edit body stats after onboarding (PRD §9 step 5). Same fields + live preview as onboarding,
/// presented as a sheet from the Trends header. Saving recomputes the target everywhere it's read.
struct ProfileSettingsSheet: View {
    @Environment(MealStore.self) private var store
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @State private var inputs = ProfileInputs()
    @State private var saving = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    TargetPreviewCard(target: inputs.target)
                    ProfileFieldsView(inputs: $inputs)
                    PremiumStatusRow(
                        isSubscribed: subscriptions.isSubscribed,
                        remainingFree: subscriptions.isSubscribed ? nil : subscriptions.remainingFreeScans,
                        onUpgrade: { showPaywall = true },
                        onManage: { Task { await subscriptions.manageSubscriptions() } })
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Palette.background)
            .navigationTitle("Your details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Theme.Palette.inkSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).tint(Theme.Palette.accent).disabled(saving)
                }
            }
            .onAppear { if let p = store.profile { inputs = ProfileInputs(p) } }
            .task { await subscriptions.refreshFreeScans() }
            .sheet(isPresented: $showPaywall) { PaywallView().environment(SubscriptionStore.shared) }
        }
    }

    private func save() {
        saving = true
        Task {
            await store.saveProfile(sex: inputs.sex, age: inputs.age,
                                    heightCm: inputs.heightCm, weightKg: inputs.weightKg,
                                    activity: inputs.activity, goal: inputs.goal)
            dismiss()
        }
    }
}

#Preview {
    ProfileSettingsSheet()
        .environment(MealStore.sample)
        .environment(SubscriptionStore.shared)
}
