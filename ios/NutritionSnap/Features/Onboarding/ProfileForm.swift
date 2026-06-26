import SwiftUI

/// Enums that render their own segmented label.
protocol Labeled { var label: String { get } }
extension BiologicalSex: Labeled {}
extension Goal: Labeled {}

/// The editable body stats behind the personal target. Shared by onboarding and Settings so both
/// show the same live Mifflin–St Jeor preview. Pure value type; the views bind to it.
struct ProfileInputs: Equatable {
    var sex: BiologicalSex = .male
    var age: Int = 30
    var heightCm: Double = 170
    var weightKg: Double = 65
    var activity: ActivityLevel = .moderate
    var goal: Goal = .maintain

    init() {}
    init(_ p: UserProfile) {
        sex = p.sex; age = p.age; heightCm = p.heightCm
        weightKg = p.weightKg; activity = p.activity; goal = p.goal
    }

    /// Live target for the current inputs — drives the preview card as the user adjusts.
    var target: Nutrients {
        NutritionMath.target(for: UserProfile(
            sex: sex, age: age, heightCm: heightCm, weightKg: weightKg,
            activity: activity, goal: goal, targets: .zero, createdAt: Date(), onboarded: true))
    }
}

/// The calm intake form (PRD §7 warm-minimal). Native pickers/steppers wrapped in surface cards so
/// it stays on-brand without re-inventing the controls. Metric units (Japan-first).
struct ProfileFieldsView: View {
    @Binding var inputs: ProfileInputs

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            card {
                segmented("You are", $inputs.sex)
                divider
                segmented("Aiming to", $inputs.goal)
            }
            card {
                intStepper("Age", $inputs.age, range: 14...100, unit: "yrs")
                divider
                doubleStepper("Height", $inputs.heightCm, range: 120...220, step: 1,
                              unit: "cm", decimals: 0)
                divider
                doubleStepper("Weight", $inputs.weightKg, range: 30...200, step: 0.5,
                              unit: "kg", decimals: 1)
            }
            card {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text("Activity").font(Theme.Typography.body).foregroundStyle(Theme.Palette.ink)
                        Spacer()
                        Picker("Activity", selection: $inputs.activity) {
                            ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) }
                        }
                        .tint(Theme.Palette.accent)
                    }
                    Text(inputs.activity.detail)
                        .font(.system(.caption))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
        }
    }

    // MARK: - Rows

    // `id: \.self` + value `.tag` keeps the selection tag the same type as the binding. Relying on
    // the enum's `Identifiable` id here makes the segmented control derive a String id-tag that
    // collides with the explicit value tag, so the binding fails to preselect (and lands on case 0).
    private func segmented<T: CaseIterable & Hashable & Labeled>(
        _ title: String, _ selection: Binding<T>) -> some View where T.AllCases: RandomAccessCollection {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).font(.system(.caption)).foregroundStyle(Theme.Palette.inkSecondary)
            Picker(title, selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func intStepper(_ title: String, _ value: Binding<Int>,
                            range: ClosedRange<Int>, unit: String) -> some View {
        HStack {
            Text(title).font(Theme.Typography.body).foregroundStyle(Theme.Palette.ink)
            Spacer()
            Text("\(value.wrappedValue) \(unit)")
                .font(Theme.Typography.body.weight(.medium)).foregroundStyle(Theme.Palette.ink)
                .monospacedDigit()
            Stepper(title, value: value, in: range).labelsHidden()
        }
    }

    private func doubleStepper(_ title: String, _ value: Binding<Double>,
                               range: ClosedRange<Double>, step: Double,
                               unit: String, decimals: Int) -> some View {
        HStack {
            Text(title).font(Theme.Typography.body).foregroundStyle(Theme.Palette.ink)
            Spacer()
            Text("\(value.wrappedValue, specifier: "%.\(decimals)f") \(unit)")
                .font(Theme.Typography.body.weight(.medium)).foregroundStyle(Theme.Palette.ink)
                .monospacedDigit()
            Stepper(title, value: value, in: range, step: step).labelsHidden()
        }
    }

    private var divider: some View {
        Divider().overlay(Theme.Palette.inkSecondary.opacity(0.15))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) { content() }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

/// The clay "on-track" card showing the computed daily target — reused by onboarding + Settings.
struct TargetPreviewCard: View {
    let target: Nutrients

    var body: some View {
        WarmCard(honey: true) {
            VStack(spacing: Theme.Spacing.xs) {
                Text("Your gentle daily target").overline()
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text("\(Int(target.kcal))").font(Theme.Typography.numeral(40))
                    Text("kcal").font(Theme.Typography.body).foregroundStyle(Theme.Palette.inkSecondary)
                }
                .foregroundStyle(Theme.Palette.ink)
                HStack(spacing: Theme.Spacing.xl) {
                    macro("Protein", target.protein)
                    macro("Carbs", target.carbs)
                    macro("Fat", target.fat)
                }
                .padding(.top, Theme.Spacing.xs)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func macro(_ label: String, _ grams: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(grams))g").font(Theme.Typography.numeral(15)).foregroundStyle(Theme.Palette.ink)
            Text(label).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
        }
    }
}

#Preview {
    @Previewable @State var inputs = ProfileInputs()
    return ScrollView {
        VStack(spacing: Theme.Spacing.lg) {
            ProfileFieldsView(inputs: $inputs)
            TargetPreviewCard(target: inputs.target)
        }
        .padding(Theme.Spacing.lg)
    }
    .background(Theme.Palette.background)
}
