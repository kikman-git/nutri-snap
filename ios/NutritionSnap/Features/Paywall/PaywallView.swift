import SwiftUI
import RevenueCat

/// Where the legal links point. Terms use Apple's standard EULA unless a custom one is hosted.
private enum PaywallLinks {
    /// Apple's standard auto-renewable-subscription EULA.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// TODO(launch): replace with the hosted privacy policy URL (we send food photos to Gemini +
    /// use Firebase) before App Store submission — see NEXT_SESSION.md "Compliance".
    static let privacy = URL(string: "https://www.apple.com/legal/privacy/")!
}

/// Custom, on-brand paywall (PRD positioning: calm, never pushy). Reads the RevenueCat `default`
/// offering — Monthly + Annual, each with a 7-day free trial — and sells/restores. Enforcement is
/// server-side (`scanMeal`); this screen only takes money. No countdowns, no dark patterns.
struct PaywallView: View {
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Package?
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    hero
                    benefits
                    if subscriptions.offering != nil {
                        plans
                        cta
                        finePrint
                    } else {
                        unavailable
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(Theme.Palette.inkSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") { Task { await restore() } }
                        .tint(Theme.Palette.inkSecondary)
                        .disabled(subscriptions.actionInFlight)
                }
            }
        }
        .task {
            await subscriptions.refreshOfferings()
            if selected == nil { selected = defaultPackage }
        }
        // A successful purchase or restore flips the entitlement → we're done here.
        .onChange(of: subscriptions.isSubscribed) { _, nowSubscribed in
            if nowSubscribed { dismiss() }
        }
        .alert("Notice", isPresented: Binding(get: { notice != nil },
                                              set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(notice ?? "") }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Palette.accent)
            Text("Nutri Snap Premium")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.ink)
            Text("Keep snapping — and let your gentle coach watch the long game with you.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            benefit("infinity", "Unlimited meal scans", "Snap every meal, every day — no counting.")
            benefit("chart.line.uptrend.xyaxis", "Full nutrient trends", "Protein, fiber, omega-3 and more, tracked over time.")
            benefit("sparkles", "Weekly reflections", "A warm, AI-written look back at how your week went.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefit(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
    }

    private var plans: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(packages, id: \.identifier) { planCard($0) }
        }
    }

    private func planCard(_ package: Package) -> some View {
        let isSelected = selected?.identifier == package.identifier
        return Button { selected = package } label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(planTitle(package))
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        if let percent = annualSavings(package) {
                            Text("Save \(percent)%")
                                .font(.system(.caption2).weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.Palette.accent, in: Capsule())
                                .foregroundStyle(Theme.Palette.surface)
                        }
                    }
                    Text(priceLine(package))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.Palette.accent
                                                : Theme.Palette.inkSecondary.opacity(0.4))
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Palette.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var cta: some View {
        Button { Task { await buy() } } label: {
            Group {
                if subscriptions.actionInFlight {
                    ProgressView().tint(Theme.Palette.surface)
                } else {
                    Text(ctaTitle).font(Theme.Typography.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Palette.accent, in: Capsule())
            .foregroundStyle(Theme.Palette.surface)
        }
        .buttonStyle(.plain)
        .disabled(subscriptions.actionInFlight || selected == nil)
    }

    private var finePrint: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("Payment is charged to your Apple ID. Your subscription renews automatically unless cancelled at least 24 hours before the period ends. Manage or cancel anytime in Settings.")
                .font(.system(.caption2))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Theme.Spacing.md) {
                Link("Terms", destination: PaywallLinks.terms)
                Text("·").foregroundStyle(Theme.Palette.inkSecondary)
                Link("Privacy", destination: PaywallLinks.privacy)
            }
            .font(.system(.caption2))
            .tint(Theme.Palette.inkSecondary)
        }
    }

    private var unavailable: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.Palette.accent)
            Text("Couldn't load plans right now.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.ink)
            Text("Check your connection and try again.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
            Button("Retry") {
                Task { await subscriptions.refreshOfferings(); selected = defaultPackage }
            }
            .tint(Theme.Palette.accent)
        }
        .padding(.vertical, Theme.Spacing.xl)
    }

    // MARK: - Actions

    private func buy() async {
        guard let package = selected ?? defaultPackage else { return }
        switch await subscriptions.purchase(package) {
        case .subscribed: break        // onChange(isSubscribed) dismisses
        case .cancelled:  break        // calm: do nothing
        case .failed:     notice = "That didn't go through — no charge was made. Please try again."
        }
    }

    private func restore() async {
        switch await subscriptions.restore() {
        case .subscribed: break
        case .cancelled:  notice = "No previous subscription was found on this Apple ID."
        case .failed:     notice = "Couldn't restore right now. Please try again in a moment."
        }
    }

    // MARK: - Derived values

    /// Annual first (it's the best value), then Monthly. Falls back to whatever the offering exposes
    /// if the standard duration accessors aren't mapped in the dashboard.
    private var packages: [Package] {
        guard let offering = subscriptions.offering else { return [] }
        let standard = [offering.annual, offering.monthly].compactMap { $0 }
        return standard.isEmpty ? offering.availablePackages : standard
    }

    private var defaultPackage: Package? { subscriptions.offering?.annual ?? packages.first }

    private var ctaTitle: String {
        (selected.map(hasFreeTrial) ?? false) ? "Start 7-day free trial" : "Subscribe"
    }

    private func hasFreeTrial(_ package: Package) -> Bool {
        package.storeProduct.introductoryDiscount?.paymentMode == .freeTrial
    }

    private func planTitle(_ package: Package) -> String {
        switch package.packageType {
        case .annual:  return "Annual"
        case .monthly: return "Monthly"
        case .weekly:  return "Weekly"
        default:       return package.storeProduct.localizedTitle
        }
    }

    private func priceLine(_ package: Package) -> String {
        let product = package.storeProduct
        let per = periodLabel(product.subscriptionPeriod)
        if hasFreeTrial(package) {
            return "7-day free trial, then \(product.localizedPriceString) / \(per)"
        }
        return "\(product.localizedPriceString) / \(per)"
    }

    private func periodLabel(_ period: SubscriptionPeriod?) -> String {
        guard let period else { return "" }
        let value = period.value
        switch period.unit {
        case .day:   return value == 1 ? "day"   : "\(value) days"
        case .week:  return value == 1 ? "week"  : "\(value) weeks"
        case .month: return value == 1 ? "month" : "\(value) months"
        case .year:  return value == 1 ? "year"  : "\(value) years"
        @unknown default: return ""
        }
    }

    /// Percentage saved by the annual plan vs. paying monthly for a year. Nil for non-annual or
    /// when the comparison can't be computed.
    private func annualSavings(_ package: Package) -> Int? {
        guard package.packageType == .annual,
              let monthly = subscriptions.offering?.monthly?.storeProduct.price else { return nil }
        let monthlyForYear = (monthly as NSDecimalNumber).doubleValue * 12
        guard monthlyForYear > 0 else { return nil }
        let annual = (package.storeProduct.price as NSDecimalNumber).doubleValue
        let percent = (1 - annual / monthlyForYear) * 100
        return percent >= 1 ? Int(percent.rounded()) : nil
    }
}

/// Compact subscription status + entry to the paywall / Apple's manage-subscriptions sheet.
/// Lives in Settings (the calm, discoverable home for it — we keep the capture screen un-nagged).
struct PremiumStatusRow: View {
    let isSubscribed: Bool
    var remainingFree: Int?
    let onUpgrade: () -> Void
    let onManage: () -> Void

    var body: some View {
        Button(action: isSubscribed ? onManage : onUpgrade) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: isSubscribed ? "checkmark.seal.fill" : "leaf.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isSubscribed ? "Nutri Snap Premium" : "Upgrade to Premium")
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary.opacity(0.6))
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if isSubscribed { return "Active · tap to manage" }
        if let remainingFree { return "\(remainingFree) free \(remainingFree == 1 ? "scan" : "scans") left" }
        return "Unlimited scans, trends & weekly reflections"
    }
}

#Preview {
    PaywallView()
        .environment(SubscriptionStore.shared)
}
