import SwiftUI

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

    private var band: DayBand { day.band(target: target) }
    private var sortedEntries: [Entry] { day.entries.sorted { $0.capturedAt < $1.capturedAt } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                summary
                if !sortedEntries.isEmpty { timeline }
                microCard
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Palette.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await prepareShare() } } label: {
                    if preparingShare { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
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
            if ProcessInfo.processInfo.environment["RENDER_SHARE"] != nil { await dumpShareCard() }
        }
    }

    private var title: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEMMMMd")
        return f.string(from: day.date)
    }

    private var summary: some View {
        WarmCard(honey: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(day.totals.kcal))").font(Theme.Typography.numeral(34)).foregroundStyle(Theme.Palette.ink)
                        Text("of \(Int(target.kcal)) kcal · \(band.gentleLabel.lowercased())")
                            .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
                    }
                    Spacer()
                    Text(dayAccent).accentLine().multilineTextAlignment(.trailing).frame(maxWidth: 120)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.6))
                        Capsule().fill(Theme.Palette.accent)
                            .frame(width: geo.size.width * min(day.totals.kcal / max(target.kcal, 1), 1))
                    }
                }
                .frame(height: 8)
                HStack(spacing: Theme.Spacing.lg) {
                    macroStat("Carbs", day.totals.carbs)
                    macroStat("Protein", day.totals.protein)
                    macroStat("Fat", day.totals.fat)
                }
            }
        }
    }

    private func macroStat(_ label: String, _ grams: Double) -> some View {
        HStack(spacing: 4) {
            Text(label).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
            Text("\(Int(grams.rounded()))g").font(Theme.Typography.numeral(13)).foregroundStyle(Theme.Palette.ink)
        }
    }

    private var dayAccent: String {
        switch band {
        case .under:   return "a lighter day"
        case .inRange: return "a steady day"
        case .over:    return "a fuller day"
        case .none:    return "a quiet day"
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionEyebrow(text: "The day")
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.Palette.bandEmpty)
                    .frame(width: 2)
                    .padding(.leading, 15)
                    .padding(.vertical, 16)
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(sortedEntries) { timelineRow($0) }
                }
            }
        }
    }

    private func timelineRow(_ entry: Entry) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            marker(entry).frame(width: 32, height: 32)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.items.first?.name ?? "Meal").font(Theme.Typography.label).foregroundStyle(Theme.Palette.ink)
                    Text("\(Int(entry.totals.kcal)) kcal\(entry.energy.map { " · \($0.label.lowercased())" } ?? "")")
                        .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
                }
                Spacer()
                Text(timeString(entry.capturedAt)).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.tabInactive)
                Menu {
                    Button { editingEntry = entry } label: { Label("Edit meal", systemImage: "pencil") }
                    Button(role: .destructive) {
                        Task { await store.delete(entry); day = await store.entries(on: day.date) }
                    } label: { Label("Remove meal", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Theme.Palette.inkSecondary)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 11)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
    }

    @ViewBuilder private func marker(_ entry: Entry) -> some View {
        if entry.photoPath != nil {
            MealPhoto(path: entry.photoPath, symbol: "fork.knife")
                .frame(width: 32, height: 32).clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(entry.energy?.tint ?? Theme.Palette.sage)
                Image(systemName: "fork.knife").font(.system(size: 13)).foregroundStyle(.white)
            }
        }
    }

    private var microCard: some View {
        WarmCard(padding: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionEyebrow(text: "Micronutrients · day total")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 2),
                          spacing: 9) {
                    ForEach(Nutrient.allCases.filter { $0 != .protein }) { n in
                        DayMicroBar(name: ShareCard.shortName(n),
                                    fraction: store.references[n] > 0 ? day.microTotals[n] / store.references[n] : 0)
                    }
                }
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("Hmm"); return f.string(from: date)
    }

    // MARK: - Share

    private func dayPhotos() -> [UIImage?] {
        day.entries.map { entry in
            entry.photoPath.flatMap { DownsampledImage.make(fromFile: LocalPhotos.url($0), maxDimension: 1080) }
        }
    }

    private func makeShareCard() -> ShareCard {
        ShareCard(date: day.date, photos: dayPhotos(),
                  totals: day.totals, micros: day.microTotals, references: store.references)
    }

    private func prepareShare() async {
        preparingShare = true
        defer { preparingShare = false }
        shareImage = ShareCardRenderer.image(for: makeShareCard())
        showShare = shareImage != nil
    }

    private func dumpShareCard() async {
        guard let image = ShareCardRenderer.image(for: makeShareCard()),
              let data = image.pngData() else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? data.write(to: docs.appendingPathComponent("share_card.png"))
    }
}

private struct DayMicroBar: View {
    let name: String
    let fraction: Double

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(name).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ink)
                .frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.bandEmpty)
                    Capsule().fill(fraction >= 0.75 ? Theme.Palette.sage : Theme.Palette.bandOver)
                        .frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 6)
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
