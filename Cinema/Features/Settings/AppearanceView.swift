import SwiftUI

/// Settings → Appearance: choose the app's single signature colour.
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
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: appearance.accentHex)
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
                            .strokeBorder(.white, lineWidth: isSelected ? 2.5 : 0)
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
