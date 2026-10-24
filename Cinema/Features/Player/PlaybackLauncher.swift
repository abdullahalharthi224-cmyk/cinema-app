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
    /// Which engine plays it.
    var engine: PlayerEngineKind = .mpv
    /// Subtitles fetched before playback started; `nil` if they weren't ready in time.
    var subtitleSources: [SubtitleSource]?

    /// Artwork for the Lock Screen.
    var artwork: URL? {
        request.history.flatMap { Artwork.background(id: $0.metaID, provided: $0.background) }
    }
}

/// Starts playback: picks the best stream automatically, or shows the list.
/// Each screen that can play owns one and attaches `.playbackLauncher(_:)`.
@MainActor
@Observable
final class PlaybackLauncher {
    var isResolving = false
    var status: Status = .findingStream

    enum Status {
        case findingStream, preparing
    }
    var session: PlaybackSession?
    var pickerRequest: StreamRequest?
    var errorMessage: String?

    private let service = ContentService()

    /// Finds the best stream for the request and plays it, or opens the
    /// stream list if nothing can be played automatically.
    func smartPlay(_ request: StreamRequest, context: ModelContext) async {
        guard !isResolving else { return }
        isResolving = true
        status = .findingStream
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
        await start(session, request: request, context: context)
    }

    /// Plays a stream the user chose from the list.
    func play(_ stream: ParsedStream, for request: StreamRequest, context: ModelContext) {
        guard let session = makeSession(for: request, preferring: stream, context: context), !isResolving else { return }
        isResolving = true
        Task {
            defer { isResolving = false }
            // Subtitles load while the stream list closes, so the player never covers it mid-animation.
            async let prepared = prepare(session, context: context)
            try? await Task.sleep(for: .milliseconds(450))
            let ready = await prepared
            if let history = request.history { WatchHistoryItem.record(history, in: context) }
            self.session = ready
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
        return await prepare(session, context: context)
    }

    private func start(_ session: PlaybackSession, request: StreamRequest, context: ModelContext) async {
        let ready = await prepare(session, context: context)
        if let history = request.history { WatchHistoryItem.record(history, in: context) }
        self.session = ready
    }

    /// Picks the engine and fetches subtitles in the preferred language in
    /// parallel, waiting at most a few seconds for subtitles so playback starts
    /// with the right ones instead of switching a moment later.
    private func prepare(_ session: PlaybackSession, context: ModelContext) async -> PlaybackSession {
        status = .preparing
        var session = session
        let settings = PlaybackSettings.shared
        let url = session.url
        let allowApple = settings.useApplePlayer
        async let engine = PlayerEngineKind.choose(for: url, allowApple: allowApple)

        if settings.preferredSubtitleLanguage != nil {
            let service = service
            let type = session.type, id = session.videoID
            let addons = Self.enabledAddons(in: context)
            let languages = settings.subtitleLanguages
            session.subtitleSources = await Self.withTimeout(seconds: 3.5) {
                await service.subtitleSources(type: type, id: id, addons: addons, preferredLanguages: languages)
            }
        }
        session.engine = await engine
        return session
    }

    /// The work's result, or `nil` if it takes longer than `seconds`.
    private static func withTimeout<T: Sendable>(
        seconds: Double, _ work: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
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
                    ResolvingIndicator(status: launcher.status)
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
    let status: PlaybackLauncher.Status

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Group {
                switch status {
                case .findingStream: Text("Finding the best stream…")
                case .preparing: Text("Preparing subtitles…")
                }
            }
            .font(.subheadline.weight(.semibold))
            .contentTransition(.opacity)
            .animation(Theme.Motion.snappy, value: status)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.l)
        .background(.ultraThinMaterial, in: .continuous(Theme.Radius.large))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}
