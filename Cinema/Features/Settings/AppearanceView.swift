import SwiftUI

/// Settings → Appearance: the theme and the app's single signature colour.
struct AppearanceView: View {
    @State private var appearance = Appearance.shared
    @State private var customColor: Color = Appearance.shared.accent

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: Theme.Spacing.l)]

    var body: some View {
        List {
            Section {
                preview
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                HStack(spacing: Theme.Spacing.m) {
                    ForEach(AppTheme.allCases) { theme in
                        themeCard(theme)
                    }
                }
                .padding(.vertical, Theme.Spacing.s)
            } header: {
                Text("Theme")
            }

            Section {
                NavigationLink(value: SettingsRoute.appIcon) {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(AppIconStore.current.previewImage)
                            .resizable()
                            .frame(width: 36, height: 36)
                            .clipShape(.continuous(8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("App Icon")
                            Text(AppIconStore.current.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                    ForEach(Appearance.presets) { preset in
                        swatch(preset)
                    }
                }
                .padding(.vertical, Theme.Spacing.s)

                ColorPicker(selection: $customColor, supportsOpacity: false) {
                    Text("Custom Color")
                }
                .onChange(of: customColor) { _, color in
                    let hex = color.hexString
                    if hex != appearance.accentHex {
                        withAnimation(Theme.Motion.spring) { appearance.accentHex = hex }
                    }
                }
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Used for highlights, ratings, progress and buttons throughout the app.")
                    .settingsFooter()
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: appearance.accentHex)
        .sensoryFeedback(.selection, trigger: appearance.theme)
    }

    private var preview: some View {
        HStack(spacing: Theme.Spacing.m) {
            QualityCapsule(text: "4K", highlighted: true)
            QualityCapsule(text: "Dolby Vision")
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.accent)
                Text(verbatim: "8.6")
                    .font(.rounded(.subheadline, weight: .bold))
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.surface, in: .continuous(Theme.Radius.medium))
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(Theme.accent)
                .frame(height: 3)
                .padding(.horizontal, Theme.Spacing.l)
        }
    }

    /// A miniature of the theme: its background, a card, a poster row and the accent.
    private func themeCard(_ theme: AppTheme) -> some View {
        let isSelected = appearance.theme == theme
        let ink: Color = theme == .light ? .black : .white
        return Button {
            withAnimation(Theme.Motion.spring) { appearance.theme = theme }
        } label: {
            VStack(spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.accent.gradient)
                        .frame(height: 26)
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(theme.surface)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .strokeBorder(ink.opacity(0.12), lineWidth: 0.5)
                                }
                                .frame(height: 30)
                        }
                    }
                    Capsule().fill(ink.opacity(0.5)).frame(width: 34, height: 4)
                    Capsule().fill(ink.opacity(0.25)).frame(width: 22, height: 4)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(theme.background, in: .continuous(Theme.Radius.small + 2))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.small + 2, style: .continuous)
                        .strokeBorder(isSelected ? Theme.accent : Color.primary.opacity(0.15), lineWidth: isSelected ? 2.5 : 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

                Text(theme.title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func swatch(_ preset: Appearance.Preset) -> some View {
        let isSelected = preset.hex.caseInsensitiveCompare(appearance.accentHex) == .orderedSame
        return Button {
            withAnimation(Theme.Motion.spring) {
                appearance.accentHex = preset.hex
                customColor = preset.color
            }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(preset.color.gradient)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: isSelected ? 2.5 : 0)
                            .padding(-5)
                    }
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(.black.opacity(0.7))
                        }
                    }
                    .scaleEffect(isSelected ? 1 : 0.9)
                Text(preset.name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
