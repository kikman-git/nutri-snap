import SwiftUI
import UIKit
import PhotosUI

struct CaptureScreen: View {
    @Environment(MealStore.self) private var store
    let model: CaptureViewModel
    @State private var pickerItem: PhotosPickerItem?
    @FocusState private var noteFocused: Bool
    @State private var editingEntry: Entry?
    @State private var spin = false

    private let clip = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)

    var body: some View {
        @Bindable var model = model
        return ZStack {
            Theme.Palette.background.ignoresSafeArea()
                .onTapGesture { noteFocused = false }

            ScrollView {
                content
                    .padding(Theme.Spacing.lg)
                    .animation(.easeInOut(duration: 0.25), value: model.phase)
                    .animation(.easeInOut(duration: 0.25), value: model.camera.status)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { noteFocused = false }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadAndReview(item) }
        }
        .sheet(item: $editingEntry) { entry in
            MealEditSheet(entry: entry) { edited in
                await store.update(edited, replacing: entry)
                model.replaceLoggedEntry(edited)
            }
        }
        .sheet(isPresented: $model.showPaywall) {
            PaywallView().environment(SubscriptionStore.shared)
        }
        .task {
            let env = ProcessInfo.processInfo.environment
            if env["AUTO_CAPTURE_FOOD"] != nil, let food = Self.documentImage("test_meal.jpg") {
                model.review(food); await model.confirm(into: store)
            } else if env["AUTO_CAPTURE"] != nil {
                model.review(Self.placeholderImage); await model.confirm(into: store)
                if env["AUTO_EDIT"] != nil { editingEntry = model.entry }
            } else if env["AUTO_REVIEW"] != nil {
                model.review(Self.placeholderImage)
                model.note = env["AUTO_REVIEW_NOTE"] ?? ""
            }
        }
    }

    // MARK: - Phase router

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:      idleView
        case .reviewing: reviewView
        case .analyzing: analyzingView
        case .logged:    loggedView
        case .notFood:
            couldntRead(title: "No meal spotted",
                        accent: "we couldn't find a meal here",
                        subtitle: model.message ?? "Try a photo of your plate — or just tell us what it was.")
        case .failed:
            couldntRead(title: "Hmm, that's a tricky one",
                        accent: "we couldn't quite read this plate",
                        subtitle: model.message ?? "Try a photo from above with the whole plate in frame.")
        }
    }

    // MARK: - Idle (viewfinder + library + most-recent)

    @ViewBuilder private var idleView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            liveViewfinder
            libraryControl
            if let recent = store.recentEntry { RecentMealRow(entry: recent) }
        }
    }

    @ViewBuilder private var liveViewfinder: some View {
        switch model.camera.status {
        case .ready:
            box(background: Theme.Palette.ink) {
                ZStack {
                    CameraPreview(session: model.camera.session)
                    ViewfinderGuides()
                    VStack {
                        Spacer()
                        Text("snap your plate, that's all")
                            .font(Theme.Typography.accent)
                            .foregroundStyle(.white)
                        Text("we'll read the calories, macros and micros")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.bottom, Theme.Spacing.lg)
                    }
                    .multilineTextAlignment(.center)
                }
            }
        case .configuring:
            fallbackBox(icon: "camera.viewfinder", title: "Starting camera…",
                        accent: "one moment")
        case .denied:
            fallbackBox(icon: "camera.fill", title: "Camera access is off",
                        accent: "turn it on in Settings, or pick from your library")
        case .unavailable:
            fallbackBox(icon: "photo.on.rectangle.angled", title: "Snap your meal",
                        accent: "choose a photo and we'll read the rest")
        }
    }

    private func fallbackBox(icon: String, title: String, accent: String) -> some View {
        box(background: Theme.Palette.surface) {
            ZStack {
                clip.strokeBorder(Theme.Palette.accent.opacity(0.22),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                VStack(spacing: Theme.Spacing.sm) {
                    illustration(icon)
                    Text(title).font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
                    Text(accent).accentLine().multilineTextAlignment(.center)
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    @ViewBuilder private var libraryControl: some View {
        if model.camera.status == .ready {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                primaryPill("Choose from library", icon: "photo.on.rectangle")
            }
        }
    }

    // MARK: - Review (slot + note → analyze)

    private var reviewView: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                circleButton("xmark") { model.retake() }
                Text("Looks good?").font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
            }

            ZStack(alignment: .bottomLeading) {
                if let image = model.image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(height: 240).frame(maxWidth: .infinity).clipped()
                }
                Chip(text: "Looks like a full plate", systemImage: "checkmark", variant: .sageTint)
                    .padding(Theme.Spacing.md)
            }
            .clipShape(clip)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionEyebrow(text: "When")
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(MealSlot.allCases) { slot in
                        Button { model.selectedSlot = slot } label: {
                            slotChip(slot.label, selected: model.selectedSlot == slot)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, Theme.Spacing.xs)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: 4) {
                    SectionEyebrow(text: "How did it feel?")
                    Text("optional").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
                }
                TextField("a satisfying lunch…", text: $model.note, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($noteFocused)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Palette.surface,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.input)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1.5))
            }
            .padding(.top, Theme.Spacing.xs)

            if let message = model.message {
                Text(message).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.accent)
            }

            Button("Read this meal") {
                noteFocused = false
                Task { await model.confirm(into: store) }
            }
            .buttonStyle(.primary)
            .padding(.top, Theme.Spacing.sm)
        }
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: Theme.Spacing.xxl)
            ZStack {
                Circle().stroke(Theme.Palette.bandEmpty, lineWidth: 5)
                Circle().trim(from: 0, to: 0.4)
                    .stroke(Theme.Palette.bandOver, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                if let image = model.image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 140, height: 140).clipShape(Circle())
                }
            }
            .frame(width: 188, height: 188)

            Text("Reading your plate").font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
            Text("finding the good stuff…").accentLine()

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                checkRow("Identified the foods", done: true)
                checkRow("Estimated portions", done: true)
                checkRow("Calculating nutrients", done: false)
            }
            .padding(.top, Theme.Spacing.md)
            Spacer(minLength: Theme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity)
        .onAppear { spin = true }
    }

    private func checkRow(_ text: String, done: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                if done {
                    Circle().fill(Theme.Palette.sage)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(Theme.Palette.bandEmpty, lineWidth: 2)
                }
            }
            .frame(width: 22, height: 22)
            Text(text)
                .font(Theme.Typography.label)
                .foregroundStyle(done ? Theme.Palette.sageText : Theme.Palette.inkSecondary)
                .opacity(done ? 1 : 0.7)
        }
    }

    // MARK: - Logged hero

    @ViewBuilder private var loggedView: some View {
        if let entry = model.entry ?? store.recentEntry {
            LoggedHeroCard(entry: entry,
                           image: model.image,
                           references: store.references,
                           dailyKcal: store.target.kcal,
                           onEdit: { editingEntry = entry },
                           onDelete: { Task { await store.delete(entry); model.reset() } })
        }
    }

    // MARK: - Couldn't read it

    private func couldntRead(title: String, accent: String, subtitle: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack { circleButton("xmark") { model.reset() }; Spacer() }
            Spacer(minLength: Theme.Spacing.xl)
            illustration("fork.knife", large: true)
            Text(title).font(Theme.Typography.title).foregroundStyle(Theme.Palette.ink)
            Text(accent).accentLine()
            Text(subtitle)
                .font(Theme.Typography.body).foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)
            Spacer(minLength: Theme.Spacing.xl)
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                primaryPill("Try another photo", icon: "camera")
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - Small shared bits

    private func primaryPill(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let icon { Image(systemName: icon) }
            Text(title)
        }
        .font(Theme.Typography.label)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.Gradient.primary, in: Capsule())
        .amberButtonShadow()
    }

    private func slotChip(_ label: String, selected: Bool) -> some View {
        Text(label)
            .font(Theme.Typography.label)
            .foregroundStyle(selected ? .white : Theme.Palette.inkSecondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(selected ? Theme.Palette.accent : Theme.Palette.background, in: Capsule())
            .overlay { if !selected { Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1.5) } }
    }

    private func circleButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .frame(width: 38, height: 38)
                .background(Theme.Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func illustration(_ icon: String, large: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.system(size: large ? 52 : 40, weight: .light))
            .foregroundStyle(Theme.Palette.accent)
            .frame(width: large ? 150 : 112, height: large ? 150 : 112)
            .background(Theme.Palette.amberTintBg, in: Circle())
    }

    private func box<Content: View>(background: Color = Theme.Palette.surface,
                                    @ViewBuilder content: () -> Content) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .background(background)
            .overlay { content() }
            .clipShape(clip)
    }

    private func loadAndReview(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = DownsampledImage.make(from: data, maxDimension: 1600) else { return }
        model.review(image)
    }

    static func documentImage(_ name: String) -> UIImage? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return DownsampledImage.make(fromFile: docs.appendingPathComponent(name), maxDimension: 1600)
    }

    static var placeholderImage: UIImage {
        let size = CGSize(width: 600, height: 800)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 0.77, green: 0.42, blue: 0.31, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            let cfg = UIImage.SymbolConfiguration(pointSize: 190, weight: .light)
            if let glyph = UIImage(systemName: "fork.knife", withConfiguration: cfg)?
                .withTintColor(UIColor(white: 1, alpha: 0.9), renderingMode: .alwaysOriginal) {
                glyph.draw(at: CGPoint(x: (size.width - glyph.size.width) / 2,
                                       y: (size.height - glyph.size.height) / 2))
            }
        }
    }
}

private struct ViewfinderGuides: View {
    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 22
            let len: CGFloat = 26
            let rect = CGRect(x: inset, y: inset,
                              width: geo.size.width - inset * 2,
                              height: geo.size.height - inset * 2)
            Path { p in
                for corner in [true, false] {
                    let y = corner ? rect.minY : rect.maxY
                    let dy: CGFloat = corner ? len : -len
                    p.move(to: CGPoint(x: rect.minX, y: y + dy)); p.addLine(to: CGPoint(x: rect.minX, y: y))
                    p.addLine(to: CGPoint(x: rect.minX + len, y: y))
                    p.move(to: CGPoint(x: rect.maxX - len, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
                    p.addLine(to: CGPoint(x: rect.maxX, y: y + dy))
                }
            }
            .stroke(Theme.Palette.surface.opacity(0.85),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Logged hero card

private struct LoggedHeroCard: View {
    let entry: Entry
    var image: UIImage?
    let references: NutrientAmounts
    let dailyKcal: Double
    var onEdit: () -> Void
    var onDelete: () -> Void

    private let bloomMicros: [Nutrient] = [.iron, .zinc, .magnesium, .potassium, .vitaminA, .vitaminC, .fiber]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            banner
            kcalRow
            if let energy = entry.energy { energyCard(energy) }
            bloomCard
            if !lowMicros.isEmpty { gapsNudge }
            actions
        }
    }

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    MealPhoto(path: entry.photoPath, symbol: entry.photoSymbol ?? "fork.knife")
                }
            }
            .frame(height: 152).frame(maxWidth: .infinity).clipped()

            LinearGradient(colors: [.clear, Theme.Palette.ink.opacity(0.62)],
                           startPoint: .center, endPoint: .bottom)
                .frame(height: 152)

            VStack(alignment: .leading, spacing: 2) {
                Text("✓ Logged · just now")
                    .font(Theme.Typography.overline).tracking(2).textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.85))
                Text(mealName).font(Theme.Typography.title).foregroundStyle(.white)
            }
            .padding(Theme.Spacing.md)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var kcalRow: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ConicRing(progress: entry.totals.kcal / max(dailyKcal, 1), lineWidth: 10) {
                VStack(spacing: 0) {
                    Text("\(Int(entry.totals.kcal.rounded()))").font(Theme.Typography.numeral(22))
                        .foregroundStyle(Theme.Palette.ink)
                    Text("kcal").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
            .frame(width: 96, height: 96)

            VStack(spacing: Theme.Spacing.sm) {
                macroRow("Carbs", entry.totals.carbs, Theme.Palette.bandOver)
                macroRow("Protein", entry.totals.protein, Theme.Palette.sage)
                macroRow("Fat", entry.totals.fat, Theme.Palette.accent)
            }
        }
    }

    private func macroRow(_ label: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 9, height: 9)
            Text(label).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ink)
            Spacer()
            Text("\(Int(grams.rounded()))g").font(Theme.Typography.numeral(13)).foregroundStyle(Theme.Palette.ink)
        }
    }

    private func energyCard(_ energy: EnergyShape) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            EnergyRibbon(energy: energy).frame(width: 60, height: 24)
            Text(energy.accentLine).accentLine().fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.amberTintBg, in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
    }

    private var bloomCard: some View {
        WarmCard(padding: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionEyebrow(text: "Micronutrient bloom · share of today")
                HStack(spacing: Theme.Spacing.md) {
                    MicroBloom(petals: MicroBloom.petals(
                        values: bloomMicros.map { entry.micros[$0] },
                        references: bloomMicros.map { references[$0] }))
                        .frame(width: 116, height: 116)
                    VStack(spacing: 6) {
                        ForEach(Array(bloomMicros.prefix(6).enumerated()), id: \.element) { i, n in
                            HStack(spacing: 5) {
                                Circle().fill(bloomColor(i)).frame(width: 8, height: 8)
                                Text(ShareCard.shortName(n))
                                    .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ink)
                                Spacer(minLength: 2)
                                Text("\(pct(n))%")
                                    .font(Theme.Typography.numeral(11)).foregroundStyle(Theme.Palette.ink)
                            }
                        }
                    }
                }
            }
        }
    }

    private var gapsNudge: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "leaf.fill").foregroundStyle(Theme.Palette.sageText)
            Text("A little low on \(lowMicros.map { $0.displayName }.joined(separator: " & ")) today")
                .font(Theme.Typography.label).foregroundStyle(Theme.Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.sageTintBg, in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button(action: onEdit) { Text("Edit") }.buttonStyle(.secondary)
            Button(role: .destructive, action: onDelete) {
                Text("Delete").frame(maxWidth: .infinity).padding(.vertical, 16)
                    .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1.5))
            }
            .font(Theme.Typography.label)
            .foregroundStyle(Theme.Palette.inkSecondary)
            .buttonStyle(.plain)
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private var mealName: String {
        let names = entry.items.map(\.name).filter { !$0.isEmpty }
        if names.isEmpty { return entry.mealSlot?.label ?? "Your meal" }
        if names.count <= 2 { return names.joined(separator: " & ") }
        return "\(names[0]) & \(names.count - 1) more"
    }

    private func bloomColor(_ i: Int) -> Color {
        [Theme.Palette.accent, Theme.Palette.sage, Theme.Palette.bandOver, Theme.Palette.honey][i % 4]
    }

    private func pct(_ n: Nutrient) -> Int {
        let r = references[n]
        return r > 0 ? Int((entry.micros[n] / r * 100).rounded()) : 0
    }

    private var lowMicros: [Nutrient] {
        Nutrient.allCases
            .map { ($0, references[$0] > 0 ? entry.micros[$0] / references[$0] : 1) }
            .filter { $0.1 < 0.5 }
            .sorted { $0.1 < $1.1 }
            .prefix(2).map(\.0)
    }
}

private struct RecentMealRow: View {
    let entry: Entry

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            MealPhoto(path: entry.photoPath, symbol: entry.photoSymbol ?? "fork.knife")
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                if entry.isLowConfidence {
                    Text("Tap to confirm what this was").font(Theme.Typography.label).foregroundStyle(Theme.Palette.ink)
                } else {
                    Text(name).font(Theme.Typography.label).foregroundStyle(Theme.Palette.ink)
                    HStack(spacing: 6) {
                        if let energy = entry.energy {
                            Circle().fill(energy.tint).frame(width: 8, height: 8)
                        }
                        Text("\(Int(entry.totals.kcal.rounded())) kcal\(entry.energy.map { " · \($0.label.lowercased())" } ?? "")")
                            .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.inkSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
    }

    private var name: String {
        let names = entry.items.map(\.name).filter { !$0.isEmpty }
        return names.first ?? entry.mealSlot?.label ?? "Your meal"
    }
}

#Preview {
    CaptureScreen(model: CaptureViewModel(estimator: MockMealEstimator()))
        .environment(MealStore.sample)
}
