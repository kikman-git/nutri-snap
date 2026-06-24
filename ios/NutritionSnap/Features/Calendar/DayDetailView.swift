import SwiftUI

/// The photo diary for one day — the emotional heart (PRD §5.3):
/// photo grid + totals vs target + a gentle balance note.
struct DayDetailView: View {
    let target: Nutrients
    @Environment(MealStore.self) private var store
    @State private var day: DayLog
    @State private var shareImage: UIImage?
    @State private var preparingShare = false
    @State private var showShare = false
    @State private var editingEntry: Entry?

    init(day: DayLog, target: Nutrients) {
        self.target = target
        _day = State(initialValue: day)
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.md)]
    private var band: DayBand { day.band(target: target) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                summary
                microCard
                photoGrid
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Palette.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await prepareShare() } } label: {
                    if preparingShare {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .tint(Theme.Palette.accent)
                .disabled(day.entries.isEmpty || preparingShare)
                .accessibilityLabel("Share this day")
            }
        }
        .sheet(isPresented: $showShare) {
            if let shareImage { ActivityView(items: [shareImage]) }
        }
        .sheet(item: $editingEntry) { entry in
            MealEditSheet(entry: entry) { edited in
                await store.update(edited, replacing: entry)
                day = await store.entries(on: day.date)
            }
        }
        .task {
            // Screenshot hook (the CLI can't open the share sheet): render the card to Documents.
            if ProcessInfo.processInfo.environment["RENDER_SHARE"] != nil { await dumpShareCard() }
        }
    }

    private var title: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMMd")
        return f.string(from: day.date)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text("\(Int(day.totals.kcal))")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("/ \(Int(target.kcal)) kcal")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                Spacer()
                Text(band.gentleLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(band.onFill)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(band.fill, in: Capsule())
            }

            MacroBar(label: "Protein", value: day.totals.protein, target: target.protein)
            MacroBar(label: "Carbs",   value: day.totals.carbs,   target: target.carbs)
            MacroBar(label: "Fat",     value: day.totals.fat,     target: target.fat)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// The day's focused micronutrients (the app tracks far more than calories). Same calm bar as
    /// the macros; protein already lives in the macro section above.
    private var microCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Micronutrients")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Palette.ink)
                Text("This day's total, vs daily reference")
                    .font(.system(.caption2))
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            ForEach(Nutrient.allCases.filter { $0 != .protein }) { n in
                MicroBar(nutrient: n, value: day.microTotals[n],
                         reference: n.referenceDaily(target: target))
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var photoGrid: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
            ForEach(day.entries) { entry in
                MealTile(entry: entry,
                         onDelete: {
                    Task {
                        await store.delete(entry)
                        day = await store.entries(on: day.date)   // reflect the removal
                    }
                }, onEdit: {
                    editingEntry = entry
                })
            }
        }
    }

    // MARK: - Share (an Instagram-ready card of the day's food + its nutrients)

    /// One image slot per meal, full-res-ish for the collage; `nil` for meals without a stored photo.
    private func dayPhotos() -> [UIImage?] {
        day.entries.map { entry in
            entry.photoPath.flatMap { DownsampledImage.make(fromFile: LocalPhotos.url($0), maxDimension: 1080) }
        }
    }

    private func makeShareCard() -> ShareCard {
        ShareCard(date: day.date, photos: dayPhotos(),
                  totals: day.totals, micros: day.microTotals, target: target)
    }

    private func prepareShare() async {
        preparingShare = true
        defer { preparingShare = false }
        shareImage = ShareCardRenderer.image(for: makeShareCard())
        showShare = shareImage != nil
    }

    /// Screenshot hook: render the card to the app's Documents so it can be pulled + inspected
    /// (the CLI can't drive the share sheet). Mirrors the AUTO_CAPTURE_* hooks.
    private func dumpShareCard() async {
        guard let image = ShareCardRenderer.image(for: makeShareCard()),
              let data = image.pngData() else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? data.write(to: docs.appendingPathComponent("share_card.png"))
    }
}

private struct MacroBar: View {
    let label: String
    let value: Double
    let target: Double

    private var fraction: Double { target > 0 ? min(value / target, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(label).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("\(Int(value)) / \(Int(target)) g")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.bandEmpty)
                    Capsule().fill(Theme.Palette.accent).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
    }
}

/// Like `MacroBar`, but for a focused micronutrient: shows its unit and formats small values.
private struct MicroBar: View {
    let nutrient: Nutrient
    let value: Double
    let reference: Double

    private var fraction: Double { reference > 0 ? min(value / reference, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(nutrient.displayName).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("\(fmt(value)) / \(fmt(reference)) \(nutrient.unit)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.bandEmpty)
                    Capsule().fill(Theme.Palette.accent).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
    }

    private func fmt(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", v) : String(Int(v.rounded()))
    }
}

private struct MealTile: View {
    let entry: Entry
    var onDelete: () -> Void
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ZStack(alignment: .topTrailing) {
                MealPhoto(path: entry.photoPath, symbol: entry.photoSymbol ?? "fork.knife")
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                Menu {
                    Button(action: onEdit) {
                        Label("Edit meal", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Remove meal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")    // tap for options (remove)
                        .font(.body)
                        .foregroundStyle(Theme.Palette.surface)
                        .shadow(color: Theme.Palette.ink.opacity(0.35), radius: 2)
                        .padding(6)
                }
            }
            Text(entry.items.first?.name ?? "Meal")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(1)
            Text("~\(Int(entry.totals.kcal)) kcal")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        DayDetailView(day: SampleData.days.first ?? DayLog(date: Date(), entries: []),
                      target: SampleData.target)
    }
    .environment(MealStore.sample)
}
