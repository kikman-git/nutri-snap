import SwiftUI
import UIKit

/// A shareable, Instagram-ready card for one day's meals — no headline, just the day's food photos
/// and their nutrients, in the app's warm palette. Gentle by design (memory: nutrition-app-direction):
/// the micro rings fill toward a daily reference and clamp at full, never red, never a pass/fail
/// score — the food is the hero, the nutrients ride along. Rendered to a `UIImage` by
/// `ShareCardRenderer` and handed to the system share sheet.
struct ShareCard: View {
    let date: Date
    /// One slot per meal that day, in order; `nil` falls back to a calm placeholder tile so a missing
    /// photo (sample / legacy data) never breaks the card.
    let photos: [UIImage?]
    let totals: Nutrients
    let micros: NutrientAmounts
    let references: NutrientAmounts

    /// 4:5 portrait authored in points; `ShareCardRenderer` scales ×3 → 1080×1350 (Instagram feed).
    static let size = CGSize(width: 360, height: 450)

    private var focusedMicros: [Nutrient] { Nutrient.allCases.filter { $0 != .protein } }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            PhotoCollage(photos: photos)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            macroRow
            ringRow
            footer
        }
        .padding(Theme.Spacing.md)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.Palette.background)
    }

    private var macroRow: some View {
        HStack(spacing: 0) {
            stat("\(Int(totals.kcal.rounded()))", "kcal")
            stat("\(Int(totals.protein.rounded()))g", "protein")
            stat("\(Int(totals.carbs.rounded()))g", "carbs")
            stat("\(Int(totals.fat.rounded()))g", "fat")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.custom("HankenGrotesk-ExtraBold", size: 17).monospacedDigit())
                .foregroundStyle(Theme.Palette.ink)
            Text(label)
                .font(.custom("HankenGrotesk-Medium", size: 9))
                .foregroundStyle(Theme.Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var ringRow: some View {
        HStack(spacing: 4) {
            ForEach(focusedMicros) { n in
                NutrientRing(value: micros[n],
                             reference: references[n],
                             name: Self.shortName(n))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// A small, tasteful wordmark — not a headline. Helps a shared card find its way home.
    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "leaf.fill").font(.system(size: 9))
            Text("Nutri Snap").font(.custom("HankenGrotesk-SemiBold", size: 10))
            Spacer()
            Text(Self.dateString(date)).font(.custom("HankenGrotesk-Medium", size: 10))
        }
        .foregroundStyle(Theme.Palette.inkSecondary)
        .padding(.top, 2)
    }

    /// Compact labels for the micro row (full names live in-app).
    static func shortName(_ n: Nutrient) -> String {
        switch n {
        case .fiber:     return "Fiber"
        case .omega3:    return "Ω-3"
        case .vitaminC:  return "Vit C"
        case .vitaminA:  return "Vit A"
        case .zinc:      return "Zinc"
        case .iron:      return "Iron"
        case .magnesium: return "Mag"
        case .protein:   return "Protein"
        case .potassium: return "K"
        case .vitaminD:  return "Vit D"
        case .b12:       return "B12"
        case .folate:    return "Folate"
        }
    }

    static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMMd")
        return f.string(from: date)
    }
}

/// The day's food, the hero of the card. Lays meals out as a clean mosaic that adapts to how many
/// there are (1 fills, 2 split, 3 = a wide one under a pair, 4 = a 2×2, 5+ shows four with a "+N").
private struct PhotoCollage: View {
    let photos: [UIImage?]
    private let gap: CGFloat = 4

    var body: some View {
        switch photos.count {
        case 0:
            tile(nil)
        case 1:
            tile(photos[0])
        case 2:
            HStack(spacing: gap) { tile(photos[0]); tile(photos[1]) }
        case 3:
            VStack(spacing: gap) {
                HStack(spacing: gap) { tile(photos[0]); tile(photos[1]) }
                tile(photos[2])
            }
        default:
            VStack(spacing: gap) {
                HStack(spacing: gap) { tile(photos[0]); tile(photos[1]) }
                HStack(spacing: gap) { tile(photos[2]); tile(photos[3], overflow: photos.count - 4) }
            }
        }
    }

    /// `Color.clear` is the layout base (flexible, splits evenly with its siblings); the photo rides
    /// as an overlay so its intrinsic size never feeds back into layout — without this an
    /// `ImageRenderer` pass lets `scaledToFill` balloon the tile and shove the rest of the card off.
    private func tile(_ image: UIImage?, overflow: Int = 0) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Theme.Palette.accent.opacity(0.12)
                        Image(systemName: "fork.knife")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.Palette.accent)
                    }
                }
            }
            .overlay {
                if overflow > 0 {
                    ZStack {
                        Color.black.opacity(0.35)
                        Text("+\(overflow)")
                            .font(.custom("HankenGrotesk-Bold", size: 22))
                            .foregroundStyle(.white)
                    }
                }
            }
            .clipped()
    }
}

/// One focused nutrient as a calm ring that fills toward its daily reference (clamped at full —
/// never over-full, never red). The amount sits inside; the name below.
private struct NutrientRing: View {
    let value: Double
    let reference: Double
    let name: String

    private var fraction: Double { reference > 0 ? min(value / reference, 1) : 0 }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(Theme.Palette.bandEmpty, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.Palette.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(amount)
                    .font(.custom("HankenGrotesk-ExtraBold", size: 9).monospacedDigit())
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 34, height: 34)
            Text(name)
                .font(.custom("HankenGrotesk-Medium", size: 8))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var amount: String {
        value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }
}

// MARK: - Rendering + sharing

/// Renders a `ShareCard` to a crisp `UIImage` for the share sheet. `ImageRenderer` is main-actor.
@MainActor
enum ShareCardRenderer {
    static func image(for card: ShareCard) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3            // 360×450 pt → 1080×1350 px
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// Thin SwiftUI bridge to the system share sheet — routes to Instagram, Messages, Save to Photos, etc.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    ShareCard(date: Date(),
              photos: [nil, nil, nil],
              totals: Nutrients(kcal: 1840, protein: 96, carbs: 210, fat: 62),
              micros: NutrientAmounts([.fiber: 18, .omega3: 1.4, .vitaminC: 72,
                                       .vitaminA: 540, .zinc: 7, .iron: 9, .magnesium: 240]),
              references: .defaultReference(proteinTarget: SampleData.target.protein))
        .padding()
        .background(Color.gray.opacity(0.2))
}
