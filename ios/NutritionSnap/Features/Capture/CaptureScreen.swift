import SwiftUI
import UIKit
import PhotosUI

/// Home tab (PRD §5.2): a live camera viewfinder → a calm **review** step (add a note) →
/// "reading…" → auto-logged card. The shutter is the raised nav-bar button (`RootView`);
/// this screen owns the viewfinder, the review panel, the result states, and the quiet
/// "choose from library" fallback. The `CaptureViewModel` (+ its `CameraSession`) is owned by `RootView`.
struct CaptureScreen: View {
    @Environment(MealStore.self) private var store
    let model: CaptureViewModel
    @State private var pickerItem: PhotosPickerItem?
    @FocusState private var noteFocused: Bool
    @State private var editingEntry: Entry?

    private let clip = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
                .onTapGesture { noteFocused = false }       // tap the field away

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    viewfinder
                    if model.phase == .reviewing {
                        reviewPanel
                    } else {
                        controls.frame(height: 60)          // fixed height so phases don't shift the layout
                        resultCard
                    }
                }
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
        .task {
            // Headless screenshot hooks (mirror RootView's START_TAB): the picker, the live camera,
            // and the keyboard can't be driven from the CLI. AUTO_CAPTURE/AUTO_CAPTURE_FOOD run the
            // full review→confirm path; AUTO_REVIEW stops on the review step so it can be captured.
            let env = ProcessInfo.processInfo.environment
            if env["AUTO_CAPTURE_FOOD"] != nil, let food = Self.documentImage("test_meal.jpg") {
                model.review(food); await model.confirm(into: store)
            } else if env["AUTO_CAPTURE"] != nil {
                model.review(Self.placeholderImage); await model.confirm(into: store)
                // AUTO_EDIT opens the edit sheet on the fresh log (pair with AUTO_EDIT_SAVE in
                // MealEditSheet to apply a canned correction — the CLI can't type or tap).
                if env["AUTO_EDIT"] != nil { editingEntry = model.entry }
            } else if env["AUTO_REVIEW"] != nil {
                model.review(Self.placeholderImage)
                model.note = env["AUTO_REVIEW_NOTE"] ?? ""
            }
        }
    }

    // MARK: - Viewfinder (switches on phase)

    @ViewBuilder private var viewfinder: some View {
        switch model.phase {
        case .idle:
            liveViewfinder(showingGuides: true)
        case .reviewing:
            box(background: Theme.Palette.ink.opacity(0.9)) {
                if let image = model.image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
        case .logged:
            // Show the shot just logged above its nutrition breakdown — the magic moment. Capped
            // height (not the full viewfinder) so the breakdown card fits without crowding.
            if let image = model.image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipShape(clip)
            } else {
                liveViewfinder(showingGuides: false)
            }
        case .analyzing:
            box(background: Theme.Palette.ink.opacity(0.04)) {
                ZStack {
                    if let image = model.image {
                        Image(uiImage: image).resizable().scaledToFill().opacity(0.45)
                    }
                    VStack(spacing: Theme.Spacing.sm) {
                        ProgressView().tint(Theme.Palette.accent)
                        Text("Reading your meal…")
                            .font(Theme.Typography.sectionTitle)
                            .foregroundStyle(Theme.Palette.ink)
                    }
                }
            }
        case .notFood:
            box {
                prompt(icon: "leaf",
                       title: "No meal spotted",
                       subtitle: model.message ?? "Hmm, I couldn't find a meal here.")
            }
        case .failed:
            box {
                prompt(icon: "cloud",
                       title: "Couldn't read that",
                       subtitle: model.message ?? "Mind trying again?")
            }
        }
    }

    /// The live feed when the camera is running, or a gentle fallback that points at the library.
    @ViewBuilder private func liveViewfinder(showingGuides: Bool) -> some View {
        switch model.camera.status {
        case .ready:
            box(background: Theme.Palette.ink.opacity(0.9)) {
                ZStack {
                    CameraPreview(session: model.camera.session)
                    if showingGuides { ViewfinderGuides() }
                }
            }
        case .configuring:
            box {
                ZStack {
                    clip.strokeBorder(Theme.Palette.accent.opacity(0.25),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    prompt(icon: "camera.viewfinder", title: "Starting camera…", subtitle: nil)
                }
            }
        case .denied:
            box {
                prompt(icon: "camera.fill",
                       title: "Camera access is off",
                       subtitle: "Turn it on in Settings — or choose a photo from your library below.")
            }
        case .unavailable:
            box {
                ZStack {
                    clip.strokeBorder(Theme.Palette.accent.opacity(0.25),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    prompt(icon: "photo.on.rectangle.angled",
                           title: "Snap your meal",
                           subtitle: "No camera here — choose a photo from your library below.")
                }
            }
        }
    }

    // MARK: - Review panel (add a note, then analyze)

    private var reviewPanel: some View {
        @Bindable var model = model
        return VStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add a note (optional)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                TextField("e.g. homemade, cooked in olive oil, large bowl",
                          text: $model.note, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($noteFocused)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Palette.surface,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }

            HStack(spacing: Theme.Spacing.md) {
                Button { model.retake() } label: {
                    Text("Retake")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.Palette.inkSecondary.opacity(0.2)))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                Button {
                    noteFocused = false
                    Task { await model.confirm(into: store) }
                } label: {
                    Label("Analyze", systemImage: "sparkles")
                        .font(Theme.Typography.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(Theme.Palette.accent, in: Capsule())
                        .foregroundStyle(Theme.Palette.surface)
                }
            }
            .font(Theme.Typography.body)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Controls (library picker; shutter lives in the nav bar)

    @ViewBuilder private var controls: some View {
        switch model.phase {
        case .idle, .logged:
            // Quiet when the camera is the primary path; promoted to a filled CTA when it isn't.
            if model.camera.status == .ready {
                picker {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
            } else {
                picker { filledCTA("Choose from library") }
            }
        case .notFood, .failed:
            picker { filledCTA("Try another photo") }
        case .reviewing, .analyzing:
            Color.clear                                   // handled elsewhere / hold the layout steady
        }
    }

    private func picker<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            label()
        }
    }

    private func filledCTA(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.body.weight(.semibold))
            .foregroundStyle(Theme.Palette.surface)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Palette.accent, in: Capsule())
    }

    // MARK: - Result card

    @ViewBuilder private var resultCard: some View {
        if model.phase == .logged, let entry = model.entry ?? store.recentEntry {
            // Fresh log: full nutrition breakdown + a quiet way to remove it.
            RecentLogCard(entry: entry,
                          image: model.image,
                          expanded: true,
                          onRemove: {
                              Task { await store.delete(entry); model.reset() }
                          },
                          onEdit: { editingEntry = entry })
        } else if model.phase == .idle, let recent = store.recentEntry {
            RecentLogCard(entry: recent, image: nil)
        }
    }

    // MARK: - Helpers

    private func box<Content: View>(background: Color = Theme.Palette.surface,
                                    @ViewBuilder content: () -> Content) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .background(background)
            .overlay { content() }
            .clipShape(clip)
    }

    private func prompt(icon: String, title: String, subtitle: String?) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.Palette.accent)
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.ink)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.lg)
    }

    private func loadAndReview(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = DownsampledImage.make(from: data, maxDimension: 1600) else { return }
        model.review(image)
    }

    /// Loads an image dropped into the app's Documents (the AUTO_CAPTURE_FOOD live-path test hook).
    static func documentImage(_ name: String) -> UIImage? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return DownsampledImage.make(fromFile: docs.appendingPathComponent(name), maxDimension: 1600)
    }

    /// Stand-in "photo" for the AUTO_CAPTURE screenshot path (no real photo needed):
    /// a warm clay field with a meal glyph so the viewfinder/thumbnail read as a captured image.
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

/// Four faint corner brackets — a calm "viewfinder" cue over the live feed.
private struct ViewfinderGuides: View {
    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 22
            let len: CGFloat = 26
            let rect = CGRect(x: inset, y: inset,
                              width: geo.size.width - inset * 2,
                              height: geo.size.height - inset * 2)
            Path { p in
                for corner in [true, false] {            // top edge, then bottom edge
                    let y = corner ? rect.minY : rect.maxY
                    let dy: CGFloat = corner ? len : -len
                    // left
                    p.move(to: CGPoint(x: rect.minX, y: y + dy)); p.addLine(to: CGPoint(x: rect.minX, y: y))
                    p.addLine(to: CGPoint(x: rect.minX + len, y: y))
                    // right
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

/// Auto-logged result as a warm summary card with a *quiet* edit affordance (PRD §5.2):
/// frictionless for the 80%, correctable for the 20%. Shows the real captured photo when
/// present; falls back to an SF Symbol for sample data.
private struct RecentLogCard: View {
    let entry: Entry
    var image: UIImage?
    /// Fresh-log card: show the full macro + micro breakdown and a quiet Remove button.
    var expanded: Bool = false
    var onRemove: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            if expanded {
                Rectangle().fill(Theme.Palette.inkSecondary.opacity(0.12)).frame(height: 1)
                MealNutrition(entry: entry)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                if entry.isLowConfidence {
                    Text("Tap to confirm what this was")          // invite, don't assert
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.ink)
                } else {
                    Text("\(mealWord) logged · ~\(Int(entry.totals.kcal)) kcal")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.ink)
                    Text(entry.balanceNote)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
            }

            Spacer()

            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash").font(Theme.Typography.caption)
                }
                .foregroundStyle(Theme.Palette.inkSecondary)
                .accessibilityLabel("Remove this meal")
            }

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil").font(Theme.Typography.caption)
                }
                .foregroundStyle(Theme.Palette.inkSecondary)
                .accessibilityLabel("Edit this meal")
            }
        }
    }

    @ViewBuilder private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(shape)
        } else {
            MealPhoto(path: entry.photoPath, symbol: entry.photoSymbol ?? "fork.knife")
                .frame(width: 44, height: 44)
                .clipShape(shape)
        }
    }

    private var mealWord: String {
        switch Calendar.current.component(.hour, from: entry.capturedAt) {
        case ..<11:   return "Breakfast"
        case 11..<15: return "Lunch"
        case 15..<18: return "Snack"
        default:      return "Dinner"
        }
    }
}

/// Macro + focused-micronutrient breakdown for one logged meal — the app tracks far more than
/// calories (memory: nutrition-app-direction). Calm + scannable: a macro row, then the seven
/// micros in two columns. Protein is in the macro row; kcal is in the card header above.
private struct MealNutrition: View {
    let entry: Entry

    private let columns = [GridItem(.flexible(), spacing: Theme.Spacing.md),
                           GridItem(.flexible(), spacing: Theme.Spacing.md)]
    private var micros: [Nutrient] { Nutrient.allCases.filter { $0 != .protein } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 0) {
                macro("Protein", entry.totals.protein)
                macro("Carbs", entry.totals.carbs)
                macro("Fat", entry.totals.fat)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(micros) { n in
                    HStack(spacing: 4) {
                        Text(n.displayName)
                            .font(.system(.caption2))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                        Spacer(minLength: 4)
                        Text("\(fmt(entry.micros[n])) \(n.unit)")
                            .font(.system(.caption2).weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                    }
                }
            }
        }
    }

    private func macro(_ label: String, _ grams: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(grams.rounded())) g")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text(label)
                .font(.system(.caption2))
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fmt(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", v) : String(Int(v.rounded()))
    }
}

#Preview {
    CaptureScreen(model: CaptureViewModel(estimator: MockMealEstimator()))
        .environment(MealStore.sample)
}
