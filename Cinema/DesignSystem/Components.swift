import SwiftUI

/// An addon's logo in a rounded square, with a tasteful monogram fallback.
struct AddonLogoView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            monogram
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.continuous(size * 0.23))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var monogram: some View {
        LinearGradient(
            colors: [hue.opacity(0.95), hue.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    /// A stable colour derived from the name so each addon keeps its own tint.
    private var hue: Color {
        let value = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: Double(value % 360) / 360, saturation: 0.55, brightness: 0.75)
    }
}

/// The coloured rounded-square icon used in Settings rows, like the system Settings app.
struct SettingsIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: .continuous(7))
            .accessibilityHidden(true)
    }
}

/// A small capsule label, e.g. "Movies" or "Search".
struct TagChip: View {
    let text: LocalizedStringKey
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// A full-screen dimmed overlay with a spinner, for short blocking operations.
struct LoadingOverlay: View {
    let title: LocalizedStringKey

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.m) {
                ProgressView()
                    .controlSize(.large)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.Spacing.xl)
            .background(.adaptiveMaterial, in: .continuous(Theme.Radius.large))
        }
        .transition(.opacity)
    }
}

/// A floating confirmation message that slides in from the top.
struct ToastView: View {
    let message: String
    var systemImage = "checkmark.circle.fill"

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .background(.adaptiveMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension View {
    /// Shows a toast for a couple of seconds whenever `message` becomes non-nil.
    func toast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .top) {
            if let text = message.wrappedValue {
                ToastView(message: text)
                    .padding(.top, Theme.Spacing.s)
                    .task(id: text) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation(.snappy) { message.wrappedValue = nil }
                    }
            }
        }
        .animation(.snappy, value: message.wrappedValue)
    }

    /// Presents an alert whenever `message` is non-nil.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(message.wrappedValue ?? "") }
        )
    }
}

extension String {
    /// Human-friendly names for the content types used by Stremio addons.
    var localizedContentType: LocalizedStringKey {
        switch self {
        case "movie": return "Movies"
        case "series": return "Series"
        case "channel": return "Channels"
        case "tv": return "Live TV"
        case "anime": return "Anime"
        case "other": return "Other"
        case "collections": return "Collections"
        default: return LocalizedStringKey(capitalized)
        }
    }
}

/// A failed load: what went wrong and a "Try Again" button, in the app's style.
struct RetryErrorView: View {
    var title: LocalizedStringKey = "Couldn't Load"
    let message: String
    var systemImage = "wifi.exclamationmark"
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(verbatim: message)
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }
}
