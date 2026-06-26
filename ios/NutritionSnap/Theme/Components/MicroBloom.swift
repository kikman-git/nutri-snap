import SwiftUI
import Foundation

/// The micronutrient "bloom" — petals radiating from a center, each petal's length ∝
/// that nutrient's share of its daily reference (capped at 100%). Decision-independent:
/// the caller maps whatever nutrient set (see plan D2) to `[Petal]`. Used on the Logged
/// hero ("share of today") and as the static Paywall emblem.
struct MicroBloom: View {
    struct Petal: Identifiable {
        let id = UUID()
        /// value / reference, clamped to 0…1 by the view.
        var fraction: Double
        var color: Color
    }

    var petals: [Petal]
    var petalWidth: CGFloat = 10
    /// Smallest visible petal so a near-zero nutrient still reads as a stub.
    var minFraction: Double = 0.08

    var body: some View {
        // Math kept out of the ViewBuilder so the type-checker stays fast.
        GeometryReader { geo in content(in: geo.size) }
            .aspectRatio(1, contentMode: .fit)
    }

    private func content(in size: CGSize) -> some View {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = side / 2 - petalWidth / 2
        return ZStack {
            Circle()
                .stroke(Theme.Palette.hairline, lineWidth: 1)
                .frame(width: side - petalWidth, height: side - petalWidth)
                .position(center)
            ForEach(Array(petals.enumerated()), id: \.element.id) { index, petal in
                petalView(index: index, petal: petal, center: center, maxR: maxR)
            }
            centerDot.position(center)
        }
    }

    private func petalView(index: Int, petal: Petal, center: CGPoint, maxR: CGFloat) -> some View {
        let n = Double(max(petals.count, 1))
        let theta = Double(index) / n * 2 * .pi - .pi / 2
        // Gentle power curve so low shares still read as a bloom (decorative emblem, not a precise bar).
        let frac = max(pow(max(min(petal.fraction, 1), 0), 0.6), minFraction)
        let length = maxR * CGFloat(frac)
        let x = center.x + CGFloat(cos(theta)) * length / 2
        let y = center.y + CGFloat(sin(theta)) * length / 2
        return Capsule()
            .fill(petal.color)
            .frame(width: petalWidth, height: length)
            .rotationEffect(.radians(theta + .pi / 2))
            .position(x: x, y: y)
    }

    private var centerDot: some View {
        Circle()
            .fill(Theme.Palette.surface)
            .frame(width: petalWidth * 1.6, height: petalWidth * 1.6)
            .overlay(Circle().fill(Theme.Palette.accent.opacity(0.25)))
    }
}

extension MicroBloom {
    /// Convenience: build petals from parallel value/reference arrays, cycling the Warm
    /// Bloom palette (clay → sage → amber → honey).
    static func petals(values: [Double], references: [Double]) -> [Petal] {
        let cycle: [Color] = [Theme.Palette.accent, Theme.Palette.sage,
                              Theme.Palette.bandOver, Theme.Palette.honey]
        return values.indices.map { i in
            let ref = i < references.count ? references[i] : 0
            let frac = ref > 0 ? values[i] / ref : 0
            return Petal(fraction: frac, color: cycle[i % cycle.count])
        }
    }
}

#Preview {
    MicroBloom(petals: MicroBloom.petals(
        values:     [101, 13, 1.0, 83, 512, 8.4, 6.6, 284],
        references: [100, 21, 2.0, 100, 900, 11, 7.5, 370]))
        .frame(width: 220, height: 220)
        .padding(Theme.Spacing.xl)
        .background(Theme.Palette.background)
}
