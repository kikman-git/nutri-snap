import SwiftUI

/// A rounded progress ring with optional center content. Used for the kcal ring (Today,
/// Logged) and the small sufficiency dials (Trends). `progress` is 0…1+ — the arc caps
/// visually at a full turn so "over target" never looks alarming.
struct ConicRing<Center: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 14
    var track: Color = Theme.Palette.bandEmpty
    var fill: Color = Theme.Palette.accent
    @ViewBuilder var center: () -> Center

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .animation(.easeOut(duration: 0.5), value: clamped)
    }
}

extension ConicRing where Center == EmptyView {
    init(progress: Double, lineWidth: CGFloat = 14,
         track: Color = Theme.Palette.bandEmpty, fill: Color = Theme.Palette.accent) {
        self.init(progress: progress, lineWidth: lineWidth, track: track, fill: fill) { EmptyView() }
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.lg) {
        ConicRing(progress: 0.82, lineWidth: 16) {
            VStack(spacing: 0) {
                Text("1,840").font(Theme.Typography.numeral(26))
                Text("kcal").font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
        .frame(width: 140, height: 140)

        ConicRing(progress: 0.6, lineWidth: 8, fill: Theme.Palette.sage) {
            Text("60%").font(Theme.Typography.numeral(15))
        }
        .frame(width: 64, height: 64)

        ConicRing(progress: 0.35, lineWidth: 8, fill: Theme.Palette.bandOver) {
            Text("35%").font(Theme.Typography.numeral(15))
        }
        .frame(width: 64, height: 64)
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Palette.background)
}
