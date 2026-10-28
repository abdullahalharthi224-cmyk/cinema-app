import SwiftData
import SwiftUI

/// The episode that follows the one playing, for the "Next Episode" button.
struct NextEpisode {
    var videoID: String
    var label: String?
    var history: WatchHistoryEntry?
    var overview: String? = nil
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
    /// Playing a downloaded file rather than streaming.
    var isLocal = false

    /// The episode's or movie's synopsis, for the pause screen.
    var overview: String? { request.overview }

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
    /// A title picked from "More Like This" at the end of a movie; opened once the player closes.
    var suggestedTitle: TMDBTitleRoute?
    var errorMessage: String?

    private let service = ContentService()

    /// Finds the best stream for the request and plays it, or opens the
    /// stream list if nothing can be played automatically.
    func smartPlay(_ request: StreamRequest, context: ModelContext) async {
        guard !isResolving else { return }
        isResolving = true
        status = .findingStream
        defer { isResolving = false }

        // Downloaded? Play the file — no link needed, works offline.
        if let item = DownloadManager.shared.completedItem(videoID: request.videoID),
           let local = localSession(for: item, request: request, context: context) {
            if let history = request.history { WatchHistoryItem.record(history, in: context) }
            session = local
            return
        }

        var request = request
        if request.prefetched == nil {
            // Once a playable link is in, slow addons get 3 more seconds rather than holding everything up.
            request.prefetched = await service.streams(
                type: request.type, id: request.videoID, addons: Self.enabledAddons(in: context), settle: .seconds(3)
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
        request.overview = next.overview
        if let item = DownloadManager.shared.completedItem(videoID: next.videoID) {
            request.next = request.upcoming.first
            request.upcoming = Array(request.upcoming.dropFirst())
            if let history = request.history { WatchHistoryItem.record(history, in: context) }
            return localSession(for: item, request: request, context: context)
        }
        request.prefetched = await service.streams(
            type: request.type, id: next.videoID, addons: Self.enabledAddons(in: context), settle: .seconds(3)
        )
        // Keep going through the season: the one after becomes "next".
        request.next = request.upcoming.first
        request.upcoming = Array(request.upcoming.dropFirst())
        guard let session = makeSession(for: request, preferring: nil, context: context) else { return nil }
        if let history = request.history { WatchHistoryItem.record(history, in: context) }
        return await prepare(session, context: context)
    }

    // MARK: Downloads

    /// Plays a download from the Downloads list.
    func playDownloaded(_ item: DownloadItem, context: ModelContext) {
        let request = Self.request(for: item)
        guard let local = localSession(for: item, request: request, context: context) else { return }
        if let history = request.history { WatchHistoryItem.record(history, in: context) }
        session = local
    }

    /// A session for a downloaded file, with its saved subtitles.
    func localSession(for item: DownloadItem, request: StreamRequest, context: ModelContext) -> PlaybackSession? {
        guard let fileName = item.fileName else { return nil }
        let url = DownloadFiles.url(for: fileName)
        var request = request
        if request.overview == nil { request.overview = item.overview }
        let saved = PlaybackProgressStore.progress(videoID: item.videoID, in: context)
        var session = PlaybackSession(
            url: url, title: request.title, subtitle: request.subtitle, type: item.type,
            metaID: item.metaID, videoID: item.videoID,
            startPosition: saved?.isResumable == true ? saved?.position ?? 0 : 0,
            next: request.next, request: request
        )
        session.isLocal = true
        let ext = url.pathExtension.lowercased()
        session.engine = PlaybackSettings.shared.useApplePlayer && !PlaybackSettings.shared.needsAudioProcessing
            && ["mp4", "m4v", "mov"].contains(ext) ? .apple : .mpv
        if let subtitle = item.subtitleFileName {
            let source = AddonSource(
                manifestURL: DownloadFiles.directory,
                manifest: AddonManifest(id: "downloaded", name: localized("Downloaded"))
            )
            let file = SubtitleItem(url: DownloadFiles.url(for: subtitle).absoluteString, lang: item.subtitleLanguage)
            session.subtitleSources = [SubtitleSource(addon: source, items: [file])]
        } else if !NetworkMonitor.shared.isConnected {
            // Offline with no saved subtitles: don't wait on addons.
            session.subtitleSources = []
        }
        return session
    }

    /// A stream request built from a download, with the downloaded episodes that follow as "next".
    static func request(for item: DownloadItem) -> StreamRequest {
        let history = WatchHistoryEntry(
            metaID: item.metaID, type: item.type, name: item.title, poster: item.poster,
            background: item.background, logo: item.logo, videoID: item.videoID,
            episodeLabel: item.episodeLabel, addonID: item.addonID
        )
        var request = StreamRequest(
            type: item.type, videoID: item.videoID, title: item.title, subtitle: item.episodeLabel,
            history: history, overview: item.overview
        )
        let position = (item.season ?? 0, item.episode ?? 0)
        let following = DownloadManager.shared.allItems()
            .filter { $0.metaID == item.metaID && $0.state == .completed && ($0.season ?? 0, $0.episode ?? 0) > position }
            .sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
            .map { next -> NextEpisode in
                var nextHistory = history
                nextHistory.videoID = next.videoID
                nextHistory.episodeLabel = next.episodeLabel
                return NextEpisode(videoID: next.videoID, label: next.episodeLabel, history: nextHistory, overview: next.overview)
            }
        request.next = following.first
        request.upcoming = Array(following.dropFirst())
        return request
    }

    /// Another playable link for the same video, skipping links that already
    /// failed, picking up at `position`.
    func alternativeSession(
        for session: PlaybackSession, excluding failed: Set<URL>, at position: Double, context: ModelContext
    ) async -> PlaybackSession? {
        var request = session.request
        if request.prefetched == nil {
            request.prefetched = await service.streams(
                type: request.type, id: request.videoID, addons: Self.enabledAddons(in: context)
            )
        }
        guard let stream = StreamRanker.best(
            in: request.prefetched ?? [], preferences: PlaybackSettings.shared.preferences, excluding: failed
        ), case .direct(let url) = stream.stream.kind else { return nil }

        var next = session
        next.url = url
        next.request = request
        next.startPosition = position
        next.engine = await PlayerEngineKind.choose(
            for: url, allowApple: PlaybackSettings.shared.useApplePlayer && !PlaybackSettings.shared.needsAudioProcessing
        )
        return next
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
        // Night mode and dialogue boost need the built-in player.
        let chosen = await engine
        session.engine = settings.needsAudioProcessing ? .mpv : chosen
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
            .navigationDestination(item: $launcher.suggestedTitle) { route in
                TMDBTitleLoaderView(route: route)
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
        .background(.adaptiveMaterial, in: .continuous(Theme.Radius.large))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}
