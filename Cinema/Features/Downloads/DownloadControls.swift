import SwiftUI

extension DownloadRequest: Identifiable {
    var id: String { videoID }
}

/// The download button on a detail page: download, progress (with pause and
/// cancel), or "downloaded" (with delete).
struct DownloadCircleButton: View {
    let videoID: String
    /// Drawn as a labelled `ActionTile` (in the detail page's action row) instead of a circle.
    var labeled = false
    let start: () -> Void

    private var manager: DownloadManager { DownloadManager.shared }

    var body: some View {
        let _ = manager.revision
        let item = manager.item(videoID: videoID)
        Group {
            if let item, manager.downloadedVideoIDs.contains(videoID) {
                Menu {
                    Button(role: .destructive) {
                        manager.delete(item)
                    } label: {
                        Label("Delete Download", systemImage: "trash")
                    }
                } label: {
                    look("Downloaded", isOn: true) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .accessibilityLabel("Downloaded")
            } else if let item, manager.pendingVideoIDs.contains(videoID) {
                Menu {
                    if item.state == .paused {
                        Button { manager.resume(item) } label: { Label("Resume Download", systemImage: "play.fill") }
                    } else {
                        Button { manager.pause(item) } label: { Label("Pause Download", systemImage: "pause.fill") }
                    }
                    Button(role: .destructive) {
                        manager.delete(item)
                    } label: {
                        Label("Cancel Download", systemImage: "xmark")
                    }
                } label: {
                    look("Downloading", isOn: true) {
                        DownloadProgressRing(fraction: manager.progress[item.id] ?? item.fraction, isPaused: item.state == .paused)
                            .frame(width: 22, height: 22)
                    }
                }
                .accessibilityLabel("Downloading")
            } else {
                Button(action: start) {
                    look("Download") { Image(systemName: "arrow.down.circle") }
                }
                .accessibilityLabel("Download")
            }
        }
        .menuStyle(.button)
        .modifier(DownloadButtonStyle(labeled: labeled))
    }

    @ViewBuilder
    private func look<Icon: View>(_ title: LocalizedStringKey, isOn: Bool = false, @ViewBuilder icon: () -> Icon) -> some View {
        if labeled {
            ActionTile(title: title, isOn: isOn, icon: icon)
        } else {
            icon()
        }
    }
}

private struct DownloadButtonStyle: ViewModifier {
    let labeled: Bool

    func body(content: Content) -> some View {
        if labeled {
            content.buttonStyle(.cardPress)
        } else {
            content.buttonStyle(.glassCircle)
        }
    }
}

/// A small ring that fills as a download progresses.
struct DownloadProgressRing: View {
    let fraction: Double
    var isPaused = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(fraction, 0.03))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: fraction)
            Image(systemName: isPaused ? "pause.fill" : "arrow.down")
                .font(.system(size: 8, weight: .black))
        }
    }
}

/// The small mark on posters and episodes that are saved for offline viewing.
struct DownloadedBadge: View {
    var body: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, Theme.accent)
            .background(Circle().fill(.black.opacity(0.35)).padding(1))
            .shadow(color: .black.opacity(0.4), radius: 3)
            .accessibilityLabel("Downloaded")
    }
}
