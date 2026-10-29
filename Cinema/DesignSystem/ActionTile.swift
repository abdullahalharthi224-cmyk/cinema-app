import SwiftUI

/// One labelled action in a row of actions (the detail page): an icon above a short caption,
/// on frosted glass. Equal widths, so a row of them lines up like Apple's own action rows.
/// When `isOn`, it takes the accent colour (e.g. a title already in My List).
struct ActionTile<Icon: View>: View {
    let title: LocalizedStringKey
    var isOn = false
    @ViewBuilder var icon: Icon

    var body: some View {
        VStack(spacing: 6) {
            icon
                .font(.system(size: 19, weight: .semibold))
                .frame(height: 24)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .foregroundStyle(isOn ? Theme.accent : .white)
        .frame(maxWidth: .infinity, minHeight: 62)
        .padding(.horizontal, 2)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(.adaptiveMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .strokeBorder(isOn ? Theme.accent.opacity(0.7) : .white.opacity(0.18), lineWidth: isOn ? 1 : 0.5)
                )
        }
        // Same frosted look as the other glass buttons on the page, in every theme.
        .environment(\.colorScheme, .dark)
        .contentShape(.continuous(Theme.Radius.medium))
    }
}

extension ActionTile where Icon == Image {
    init(_ title: LocalizedStringKey, systemImage: String, isOn: Bool = false) {
        self.init(title: title, isOn: isOn) { Image(systemName: systemImage) }
    }
}
