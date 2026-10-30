import SwiftUI

/// "Made with love by Abdullah", with a link to support the developer.
/// Shown at the bottom of the side menu and of Settings.
struct MadeWithLove: View {
    static let supportURL = URL(string: "https://creators.sa/a3r")!
    static let author = "Abdullah"

    var compact = false

    var body: some View {
        VStack(spacing: compact ? Theme.Spacing.s : Theme.Spacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, options: .repeating.speed(0.5))
                    .accessibilityHidden(true)
                Text("Made with love by \(Text(verbatim: Self.author).fontWeight(.bold))")
            }
            .font(compact ? .footnote : .subheadline)
            .foregroundStyle(Theme.secondaryText)

            Link(destination: Self.supportURL) {
                Label("Support the Developer", systemImage: "cup.and.saucer.fill")
                    .font((compact ? Font.footnote : .subheadline).weight(.semibold))
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, compact ? 8 : 10)
                    .foregroundStyle(Theme.accent)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
            }
            .accessibilityHint(Text(verbatim: "creators.sa"))
        }
        .frame(maxWidth: .infinity)
    }
}
