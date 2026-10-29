import SwiftUI
import UIKit

/// One of the app icon styles bundled with Cinema.
enum AppIconStyle: String, CaseIterable, Identifiable {
    case original, light, dark, gold, neon, terminal, retro, aqua

    var id: String { rawValue }

    /// The alternate icon's name in the asset catalog (nil for the main icon).
    var iconName: String? {
        self == .original ? nil : "AppIcon-" + previewSuffix
    }

    var previewImage: String { "IconPreview-" + previewSuffix }

    private var previewSuffix: String {
        switch self {
        case .original: return "Original"
        case .light: return "Light"
        case .dark: return "Dark"
        case .gold: return "Gold"
        case .neon: return "Neon"
        case .terminal: return "Terminal"
        case .retro: return "Retro"
        case .aqua: return "Aqua"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .original: return "Original"
        case .light: return "Daylight"
        case .dark: return "Midnight"
        case .gold: return "Royal Gold"
        case .neon: return "Neon Glow"
        case .terminal: return "Green Code"
        case .retro: return "Retro Sunset"
        case .aqua: return "Aqua Glass"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .original: return "Gold on black, the classic look"
        case .light: return "Simple and bright"
        case .dark: return "Simple and dark"
        case .gold: return "Brushed gold, black lacquer"
        case .neon: return "Pink and orange glow on black"
        case .terminal: return "Green on black, faint lines of code"
        case .retro: return "Purple and pink, sunset grid"
        case .aqua: return "Glossy glass and water blue"
        }
    }

    init(iconName: String?) {
        self = Self.allCases.first { $0.iconName == iconName } ?? .original
    }
}

/// Keeps the chosen icon in settings too, so backups can bring it back.
@MainActor
enum AppIconStore {
    static let key = "appearance.appIcon"

    static var current: AppIconStyle {
        AppIconStyle(iconName: UIApplication.shared.alternateIconName)
    }

    static func apply(_ style: AppIconStyle) async throws {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        if UIApplication.shared.alternateIconName != style.iconName {
            try await UIApplication.shared.setAlternateIconName(style.iconName)
        }
        UserDefaults.standard.set(style.rawValue, forKey: key)
    }

    /// After a restore: switches to the icon saved in settings, if it differs.
    static func applySaved() async {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let style = AppIconStyle(rawValue: raw), style != current
        else { return }
        try? await apply(style)
    }
}

/// Settings → Appearance → App Icon: a large preview of every style.
struct AppIconView: View {
    @State private var selected = AppIconStore.current
    @State private var failed = false

    var body: some View {
        List {
            Section {
                ForEach(AppIconStyle.allCases) { style in
                    row(style)
                }
            } footer: {
                Text("iOS confirms the change with a short message.")
                    .settingsFooter()
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selected)
        .alert("Couldn't Change the Icon", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func row(_ style: AppIconStyle) -> some View {
        let isSelected = style == selected
        return Button {
            choose(style)
        } label: {
            HStack(spacing: Theme.Spacing.l) {
                Image(style.previewImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 84, height: 84)
                    .clipShape(.continuous(19))
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(style.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(style.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ style: AppIconStyle) {
        guard style != selected else { return }
        let previous = selected
        withAnimation(Theme.Motion.spring) { selected = style }
        Task {
            do {
                try await AppIconStore.apply(style)
            } catch {
                withAnimation(Theme.Motion.spring) { selected = previous }
                failed = true
            }
        }
    }
}
