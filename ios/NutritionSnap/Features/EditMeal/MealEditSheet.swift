import SwiftUI

struct MealEditSheet: View {
    let entry: Entry
    let onSave: (Entry) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var editableItems: [EditableFoodItem]
    @State private var microValues: [Nutrient: String]
    @State private var isSaving = false

    private let focusedNutrients = Nutrient.allCases.filter { $0 != .protein }

    init(entry: Entry, onSave: @escaping (Entry) async -> Void) {
        self.entry = entry
        self.onSave = onSave
        _editableItems = State(initialValue: entry.items.map { EditableFoodItem(item: $0) })
        _microValues = State(initialValue: Dictionary(uniqueKeysWithValues: Nutrient.allCases.map { nutrient in
            (nutrient, Self.formatValue(entry.micros[nutrient]))
        }))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    VStack(spacing: Theme.Spacing.md) {
                        ForEach($editableItems) { item in
                            itemCard(item)
                        }
                    }

                    microSection

                    totalsPreview
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Palette.background)
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .disabled(isSaving)
                }
            }
            .task {
                // Headless hook (CLI can't type): apply a canned correction through the real
                // save path so edits can be regression-tested end-to-end. See CLAUDE.md hooks.
                guard ProcessInfo.processInfo.environment["AUTO_EDIT_SAVE"] != nil else { return }
                try? await Task.sleep(for: .seconds(1.5))      // let the sheet finish presenting
                if !editableItems.isEmpty {
                    editableItems[0].name += " (edited)"
                    editableItems[0].kcal = "800"
                }
                microValues[.fiber] = "9.9"
                await save()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Review values as you saw them")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.ink)
            Text("Make quick corrections to item details, macros, and focused micros.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
    }

    @ViewBuilder private func itemCard(_ item: Binding<EditableFoodItem>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Item")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)

            VStack(spacing: Theme.Spacing.sm) {
                TextField("Name", text: item.name)
                    .textInputAutocapitalization(.sentences)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))

                TextField("Portion", text: item.portion)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))

                HStack(spacing: Theme.Spacing.sm) {
                    numericField("kcal", value: item.kcal)
                    numericField("Protein", value: item.protein)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    numericField("Carbs", value: item.carbs)
                    numericField("Fat", value: item.fat)
                    numericField("Confidence", value: item.confidence)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func numericField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)

            TextField("0", text: value)
                .keyboardType(.decimalPad)
                .padding(Theme.Spacing.sm)
                .background(Theme.Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
    }

    private var microSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Focused micros")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(focusedNutrients) { nutrient in
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(nutrient.displayName)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("(\(nutrient.unit))")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkSecondary)
                        TextField("0", text: binding(for: nutrient))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .padding(Theme.Spacing.sm)
                            .frame(width: 100)
                            .background(Theme.Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private var totalsPreview: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Meal total")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)

            HStack {
                Text("~\(Int(recalculatedTotals.kcal)) kcal")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("P \(fmt(recalculatedTotals.protein))")
                Text("C \(fmt(recalculatedTotals.carbs))")
                Text("F \(fmt(recalculatedTotals.fat))")
            }
            .font(.system(.caption).weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSecondary)
        }
    }

    private var recalculatedTotals: Nutrients {
        editableItems.reduce(.zero) { totals, item in
            totals + Nutrients(kcal: item.kcalValue,
                               protein: item.proteinValue,
                               carbs: item.carbsValue,
                               fat: item.fatValue)
        }
    }

    private var editedMicros: NutrientAmounts {
        let values = Dictionary(uniqueKeysWithValues: focusedNutrients.map { nutrient in
            (nutrient.rawValue, parsedDouble(microValues[nutrient]))
        })
        return NutrientAmounts(values: values)
    }

    private func binding(for nutrient: Nutrient) -> Binding<String> {
        Binding(
            get: { microValues[nutrient, default: ""] },
            set: { microValues[nutrient] = $0 }
        )
    }

    private func save() async {
        isSaving = true

        let items = editableItems.map { item in
            FoodItem(id: item.id,
                     name: item.name,
                     portion: item.portion,
                     kcal: item.kcalValue,
                     protein: item.proteinValue,
                     carbs: item.carbsValue,
                     fat: item.fatValue,
                     confidence: item.confidenceValue)
        }

        let updated = Entry(id: entry.id,
                           capturedAt: entry.capturedAt,
                           source: entry.source,
                           edited: true,
                           items: items,
                           totals: recalculatedTotals,
                           micros: editedMicros,
                           balanceNote: entry.balanceNote,
                           photoSymbol: entry.photoSymbol,
                           photoPath: entry.photoPath)

        await onSave(updated)
        isSaving = false
        dismiss()
    }

    private func parsedDouble(_ value: String?) -> Double {
        guard let value else { return 0 }
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? 0
    }

    private static func formatValue(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }

    private func fmt(_ value: Double) -> String {
        Self.formatValue(value)
    }
}

private struct EditableFoodItem: Identifiable {
    let id: UUID
    var name: String
    var portion: String
    var kcal: String
    var protein: String
    var carbs: String
    var fat: String
    var confidence: String

    init(item: FoodItem) {
        id = item.id
        name = item.name
        portion = item.portion
        kcal = String(format: "%.2f", item.kcal)
        protein = String(format: "%.2f", item.protein)
        carbs = String(format: "%.2f", item.carbs)
        fat = String(format: "%.2f", item.fat)
        confidence = String(format: "%.2f", item.confidence)
    }

    var kcalValue: Double { parsed(kcal) }
    var proteinValue: Double { parsed(protein) }
    var carbsValue: Double { parsed(carbs) }
    var fatValue: Double { parsed(fat) }
    var confidenceValue: Double { parsed(confidence) }

    private func parsed(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}

#Preview {
    MealEditSheet(entry: SampleData.recentEntry ?? Entry(capturedAt: Date(), source: .vision,
                                                        edited: false, items: [],
                                                        totals: .zero, micros: .zero,
                                                        balanceNote: "", photoSymbol: "fork.knife")) { _ in }
}
