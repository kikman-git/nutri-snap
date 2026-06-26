import SwiftUI

/// Uppercase tracked overline that sits atop most cards/sections.
struct SectionEyebrow: View {
    let text: String
    var body: some View {
        Text(text).overline()
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
        SectionEyebrow(text: "Today")
        SectionEyebrow(text: "Nutrient sufficiency")
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Palette.background)
}
