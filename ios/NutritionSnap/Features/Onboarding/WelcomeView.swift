import SwiftUI

/// Welcome / first launch (Warm Bloom screen 1) — the value-prop splash before the profile form.
/// Anonymous, no login, so the design's "Sign in" line is dropped (D7). "Get started" → profile.
struct WelcomeView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            SpotIllustration().frame(width: 200, height: 200)
            cameraMark
            Text("Nutri Snap").font(.custom("HankenGrotesk-ExtraBold", size: 34)).foregroundStyle(Theme.Palette.ink)
            Text("a calmer way to eat —\nsnap, and we'll read the rest")
                .font(.custom("Newsreader-Italic", size: 20)).foregroundStyle(Theme.Palette.accent)
                .multilineTextAlignment(.center).lineSpacing(2)
            Text("No counting, no scolding. Just a gentle read of your energy and the nutrients you're getting.")
                .font(Theme.Typography.body).foregroundStyle(Theme.Palette.inkSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, Theme.Spacing.md)
            Spacer()
            Button("Get started", action: onStart).buttonStyle(.primary)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background.ignoresSafeArea())
    }

    private var cameraMark: some View {
        BrandIcon.Camera()
            .stroke(.white, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
            .frame(width: 26, height: 26)
            .frame(width: 56, height: 56)
            .background(Theme.Gradient.primary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .amberButtonShadow()
            .padding(.top, Theme.Spacing.xs)
    }
}

/// The warm spot illustration — a sage-tint disc with an amber sun rising over soft sage hills.
private struct SpotIllustration: View {
    var body: some View {
        ZStack {
            Circle().fill(Theme.Palette.sageTintBg)
            ZStack {
                Circle().fill(Theme.Gradient.primary)
                    .frame(width: 58, height: 58).offset(y: -18)
                Hill(crest: 0.62).fill(Theme.Palette.sage.opacity(0.8))
                Hill(crest: 0.76).fill(Theme.Palette.sage)
            }
            .clipShape(Circle())
            Sparkles().stroke(Theme.Palette.bandOver, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct Hill: Shape {
    var crest: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let base = r.height * crest
        p.move(to: CGPoint(x: 0, y: base))
        p.addCurve(to: CGPoint(x: r.width, y: base),
                   control1: CGPoint(x: r.width * 0.33, y: base - r.height * 0.12),
                   control2: CGPoint(x: r.width * 0.66, y: base + r.height * 0.10))
        p.addLine(to: CGPoint(x: r.width, y: r.height))
        p.addLine(to: CGPoint(x: 0, y: r.height))
        p.closeSubpath()
        return p
    }
}

private struct Sparkles: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for c in [CGPoint(x: r.width * 0.24, y: r.height * 0.34),
                  CGPoint(x: r.width * 0.78, y: r.height * 0.38)] {
            p.move(to: CGPoint(x: c.x - 4, y: c.y + 3)); p.addLine(to: CGPoint(x: c.x, y: c.y - 4))
            p.addLine(to: CGPoint(x: c.x + 4, y: c.y + 3))
        }
        return p
    }
}

#Preview { WelcomeView(onStart: {}) }
