import SwiftData
import SwiftUI

/// The episode that follows the one playing, for the "Next Episode" button.
struct NextEpisode {
    var videoID: String
    var label: String?
    var history: WatchHistoryEntry?
}

/// Everything the player needs to start one video.
struct PlaybackSession: Identifiable {
    let id = UUID()
    var url: URL
    var title: String
    var subtitle: String?
    var type: String
    var metaID: String
    var videoID: String
    /// Seconds to resume from.
    var startPosition: Double
    var next: NextEpisode?
    /// The stream request this came from, for "Other Streams" in the player.
    var request: StreamRequest
}

/// Starts playback: picks the best stream automatically, or shows the list.
/// Each screen that can play owns one and attaches `.playbackLauncher(_:)`.
@MainActor
@Observable
final class PlaybackLauncher {
    var isResolving = false
    var session: PlaybackSession?
    var pickerRequest: StreamRequest?
    var errorMessage: String?

    private let service = ContentService()

    /// Finds the best stream for the request and plays it, or opens the
    /// stream list if nothing can be played automatically.
    func smartPlay(_ request: StreamRequest, context: ModelContext) async {
        guard !isResolving else { return }
        isResolving = true
        defer { isResolving = false }

        var request = request
        if request.prefetched == nil {
            request.prefetched = await service.streams(
                type: request.type, id: request.videoID, addons: Self.enabledAddons(in: context)
            )
        }
        guard let session = makeSession(for: request, preferring: nil, context: context) else {
            pickerRequest = request
            return
        }
        start(session, request: request, context: context)
    }

    /// Plays a stream the user chose from the list.
    func play(_ stream: ParsedStream, for request: StreamRequest, context: ModelContext) {
        guard let session = makeSession(for: request, preferring: stream, context: context) else { return }
        // Let the stream list finish closing before the player covers the screen.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            start(session, request: request, context: context)
        }
    }

    /// Resolves the next episode's best stream, for the player's "Next Episode" button.
    func session(for next: NextEpisode, after current: PlaybackSession, context: ModelContext) async -> PlaybackSession? {
        var request = current.request
        request.videoID = next.videoID
        request.subtitle = next.label
        request.history = next.history
        request.prefetched = await service.streams(
            type: request.type, id: next.videoID, addons: Self.enabledAddons(in: context)
        )
        request.next = nil
        guard let session = makeSession(for: request, preferring: nil, context: context) else { return nil }
        if let history = request.history { WatchHistoryItem.record(history, in: context) }
        return session
    }

    private func start(_ session: PlaybackSession, request: StreamRequest, context: ModelContext) {
        if let history = request.history { WatchHistoryItem.record(history, in: context) }
        self.session = session
    }

    private func makeSession(for request: StreamRequest, preferring chosen: ParsedStream?, context: ModelContext) -> PlaybackSession? {
        let stream = chosen ?? StreamRanker.best(in: request.prefetched ?? [], preferences: PlaybackSettings.shared.preferences)
        guard let stream, case .direct(let url) = stream.stream.kind else { return nil }

        let saved = PlaybackProgressStore.progress(videoID: request.videoID, in: context)
        return PlaybackSession(
            url: url,
            title: request.title,
            subtitle: request.subtitle,
            type: request.type,
            metaID: request.history?.metaID ?? request.videoID,
            videoID: request.videoID,
            startPosition: saved?.isResumable == true ? saved?.position ?? 0 : 0,
            next: request.next,
            request: request
        )
    }

    static func enabledAddons(in context: ModelContext) -> [AddonSource] {
        let descriptor = FetchDescriptor<InstalledAddon>(
            predicate: #Predicate { $0.isEnabled }, sortBy: [SortDescriptor(\.sortIndex)]
        )
        return ((try? context.fetch(descriptor)) ?? []).sources
    }
}

extension View {
    /// Adds the "finding the best stream" indicator, the stream list and the player.
    func playbackLauncher(_ launcher: PlaybackLauncher) -> some View {
        modifier(PlaybackLauncherModifier(launcher: launcher))
    }
}

private struct PlaybackLauncherModifier: ViewModifier {
    @Bindable var launcher: PlaybackLauncher
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .overlay {
                if launcher.isResolving {
                    ResolvingIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(Theme.Motion.spring, value: launcher.isResolving)
            .sheet(item: $launcher.pickerRequest) { request in
                StreamPickerView(request: request) { stream in
                    launcher.play(stream, for: request, context: context)
                }
            }
            .fullScreenCover(item: $launcher.session) { session in
                PlayerView(session: session, launcher: launcher)
            }
    }
}

private struct ResolvingIndicator: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Finding the best stream…")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.l)
        .background(.ultraThinMaterial, in: .continuous(Theme.Radius.large))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}
