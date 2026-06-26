import SwiftUI

struct EnergyRibbon: View {
    let energy: EnergyShape
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            EnergyRibbonShape(energy: energy, filled: true)
                .fill(energy.tint.opacity(0.10))
            EnergyRibbonShape(energy: energy)
                .stroke(energy.tint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct EnergyRibbonShape: Shape {
    let energy: EnergyShape
    var filled = false

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 280, sy = rect.height / 70
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
        var path = Path()
        switch energy {
        case .steady:
            path.move(to: p(0, 46))
            path.addCurve(to: p(140, 40), control1: p(60, 40), control2: p(90, 42))
            path.addCurve(to: p(280, 36), control1: p(190, 38), control2: p(230, 38))
        case .gentleRise:
            path.move(to: p(0, 50))
            path.addCurve(to: p(150, 22), control1: p(70, 48), control2: p(100, 18))
            path.addCurve(to: p(280, 48), control1: p(200, 26), control2: p(220, 46))
        case .spike:
            path.move(to: p(0, 54))
            path.addCurve(to: p(110, 8), control1: p(50, 52), control2: p(70, 8))
            path.addCurve(to: p(210, 58), control1: p(150, 8), control2: p(160, 60))
            path.addCurve(to: p(280, 50), control1: p(240, 57), control2: p(260, 50))
        }
        if filled {
            path.addLine(to: p(280, 70))
            path.addLine(to: p(0, 70))
            path.closeSubpath()
        }
        return path
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.lg) {
        ForEach(EnergyShape.allCases) { e in
            HStack(spacing: Theme.Spacing.md) {
                EnergyRibbon(energy: e).frame(width: 80, height: 30)
                Text(e.accentLine).accentLine()
                Spacer()
            }
        }
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Palette.background)
}
