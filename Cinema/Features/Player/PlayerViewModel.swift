import AVFoundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class PlayerViewModel {
    private(set) var session: PlaybackSession
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPaused = false
    private(set) var isBuffering = true
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var audioTracks: [MPVTrack] = []
    private(set) var subtitleTracks: [MPVTrack] = []
    private(set) var speed: Double = 1
    private(set) var isLoadingNext = false
    private(set) var subtitleSources: [SubtitleSource] = []
    private(set) var isLoadingSubtitles = false
    private(set) var subtitleDelay: Double = 0
    private(set) var subtitleRaise: Double = 40
    private(set) var sync: SyncState = .idle
    private var controlsVisible = true
    /// The exact playback time, without the UI throttling applied to `position`.
    @ObservationIgnored private var precisePosition: Double = 0
    @ObservationIgnored private var cueCache: [String: [SubtitleCue]] = [:]
    var isScrubbing = false
    var scrubPosition: Double = 0

    private var handle: MPVHandle?
    private var lastSavedPosition: Double = 0
    private var addedSubtitles = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var wasPlayingBeforeBackground = false
    private weak var context: ModelContext?
    private let launcher: PlaybackLauncher

    /// The lines of the subtitle on screen, for tap-to-sync.
    enum SyncState: Equatable {
        case idle
        case loading
        case ready(url: String, cues: [SubtitleCue])
        /// Subtitles inside the video file can't be listed.
        case embeddedOnly
        case noSubtitle
        case failed
    }

    static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    init(session: PlaybackSession, launcher: PlaybackLauncher) {
        self.session = session
        self.launcher = launcher
    }

    var displayedPosition: Double { isScrubbing ? scrubPosition : position }
    var remaining: Double { max(duration - displayedPosition, 0) }

    /// Offer the next episode during the last 90 seconds (or 5%) of an episode.
    var showsNextEpisode: Bool {
        guard session.next != nil, duration > 0 else { return false }
        return remaining <= max(90, duration * 0.05)
    }

    // MARK: Lifecycle

    func attach(to controller: MPVVideoViewController, context: ModelContext) {
        guard handle == nil else { return }
        self.context = context
        let languages = PlaybackSettings.shared.subtitleLanguages
        var options: [String: String] = [:]
        options["sub-font-size"] = String(PlaybackSettings.shared.subtitleSize.fontSize)
        if languages.isEmpty {
            options["sid"] = "no"
        } else {
            // Embedded subtitles in the preferred language are picked automatically.
            options["slang"] = languages.flatMap { [$0, Self.threeLetterCode($0)] }.joined(separator: ",")
        }
        guard let handle = MPVHandle(layer: controller.metalLayer, options: options) else {
            errorMessage = localized("The player couldn't start.")
            return
        }
        handle.onEvent = { [weak self] event in self?.process(event) }
        self.handle = handle

        observeAppLifecycle()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.isIdleTimerDisabled = true

        load(session)
    }

    private func load(_ session: PlaybackSession) {
        hasLoaded = false
        isBuffering = true
        addedSubtitles = false
        subtitleSources = []
        subtitleDelay = 0
        position = session.startPosition
        precisePosition = session.startPosition
        sync = .idle
        duration = 0
        lastSavedPosition = session.startPosition
        handle?.setString("start", session.startPosition > 0 ? String(Int(session.startPosition)) : "none")
        handle?.setDouble("sub-delay", 0)
        handle?.command(["loadfile", session.url.absoluteString, "replace"])
        handle?.setFlag("pause", false)
    }

    func close() {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycleObservers = []
        saveProgress()
        handle?.destroy()
        handle = nil
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Pauses in the background and restores the picture on return (the GPU
    /// surface is lost while the app is in the background).
    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.wasPlayingBeforeBackground = !self.isPaused
                    self.handle?.setFlag("pause", true)
                    self.handle?.setString("vid", "no")
                    self.saveProgress()
                }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.handle?.setString("vid", "auto")
                    if self.wasPlayingBeforeBackground { self.handle?.setFlag("pause", false) }
                }
            },
        ]
    }

    /// Lifts subtitles above the controls while they're on screen.
    func controlsVisibilityChanged(_ visible: Bool) {
        controlsVisible = visible
        applySubtitleMargin()
    }

    private func applySubtitleMargin() {
        let margin = subtitleRaise + (controlsVisible ? 110 : 0)
        handle?.setString("sub-margin-y", String(Int(margin)))
    }

    func setSubtitleSize(_ size: PlaybackSettings.SubtitleSize) {
        PlaybackSettings.shared.subtitleSize = size
        handle?.setString("sub-font-size", String(size.fontSize))
    }

    /// Positive shows subtitles later, negative earlier (seconds).
    func adjustSubtitleDelay(by step: Double) {
        setSubtitleDelay(((subtitleDelay + step) * 100).rounded() / 100)
    }

    func setSubtitleDelay(_ seconds: Double) {
        subtitleDelay = seconds
        handle?.setDouble("sub-delay", seconds)
    }

    /// How high subtitles sit above the bottom of the picture.
    func setSubtitleRaise(_ value: Double) {
        subtitleRaise = value
        applySubtitleMargin()
    }

    // MARK: Events

    private func process(_ event: MPVEvent) {
        switch event {
        case .position(let value):
            // libmpv reports every frame; a few updates a second is plenty for the UI.
            precisePosition = value
            if abs(value - position) >= 0.25 || value < position { position = value }
            if abs(value - lastSavedPosition) >= 10 { saveProgress() }
        case .duration(let value):
            duration = value
        case .paused(let paused):
            isPaused = paused
            if paused { saveProgress() }
        case .buffering(let buffering):
            isBuffering = buffering
        case .endReached(let ended):
            if ended {
                saveProgress()
                isPaused = true
            }
        case .fileLoaded:
            hasLoaded = true
            isBuffering = false
            refreshTracks { [weak self] in
                Task { await self?.loadSubtitleSources() }
            }
        case .tracksChanged:
            refreshTracks()
        case .loadFailed(let reason):
            errorMessage = localized("This stream couldn't be played (%@). Try another one.", reason)
        }
    }

    private func refreshTracks(then completion: (() -> Void)? = nil) {
        guard let handle else { return }
        handle.fetchTracks { [weak self] tracks in
            guard let self else { return }
            audioTracks = tracks.filter { $0.kind == .audio }
            subtitleTracks = tracks.filter { $0.kind == .sub }
            completion?()
        }
    }

    // MARK: Subtitles

    /// Subtitles inside the video file.
    var embeddedSubtitles: [MPVTrack] { subtitleTracks.filter { !$0.isExternal } }

    var isSubtitleOff: Bool { subtitleTracks.allSatisfy { !$0.isSelected } }

    /// The addon subtitle currently showing, by URL.
    var selectedSubtitleURL: String? {
        subtitleTracks.first { $0.isSelected && $0.isExternal }?.externalFilename
    }

    /// Fetches what every subtitle addon offers. If the file has nothing in the
    /// preferred language, the best match is turned on automatically.
    private func loadSubtitleSources() async {
        guard !addedSubtitles, let context else { return }
        addedSubtitles = true
        isLoadingSubtitles = true
        defer { isLoadingSubtitles = false }

        let languages = PlaybackSettings.shared.subtitleLanguages
        let sources = await ContentService().subtitleSources(
            type: session.type, id: session.videoID,
            addons: PlaybackLauncher.enabledAddons(in: context),
            preferredLanguages: languages.isEmpty ? ["ar", "en"] : languages
        )
        guard handle != nil else { return }
        subtitleSources = sources

        guard let preferred = languages.first else { return }
        let embeddedPreferred = embeddedSubtitles.contains { SubtitleLanguage.code(for: $0.language) == preferred }
        if !embeddedPreferred,
           let best = sources.lazy.flatMap(\.items).first(where: { SubtitleLanguage.code(for: $0.lang) == preferred }) {
            selectExternalSubtitle(best)
        }
    }

    /// Shows a subtitle from an addon, loading it the first time it's picked.
    func selectExternalSubtitle(_ item: SubtitleItem) {
        if let loaded = subtitleTracks.first(where: { $0.externalFilename == item.url }) {
            selectSubtitle(loaded)
            return
        }
        let code = SubtitleLanguage.code(for: item.lang)
        let name = Self.languageName(code) ?? item.lang ?? localized("Subtitles")
        handle?.command(["sub-add", item.url, "select", name, code ?? ""])
        refreshTracks()
    }

    // MARK: Smart sync

    /// Loads the lines of the subtitle currently showing so the viewer can tap
    /// one the moment they hear it.
    func prepareSync() async {
        guard let url = selectedSubtitleURL else {
            sync = subtitleTracks.contains(where: \.isSelected) ? .embeddedOnly : .noSubtitle
            return
        }
        if case .ready(let loaded, _) = sync, loaded == url { return }
        if let cached = cueCache[url] {
            sync = .ready(url: url, cues: cached)
            return
        }
        guard let address = URL(string: url) else {
            sync = .failed
            return
        }
        sync = .loading
        do {
            let (data, _) = try await URLSession.shared.data(from: address)
            let cues = await Task.detached { SubtitleParser.parse(data) }.value
            guard selectedSubtitleURL == url else { return }
            if cues.isEmpty {
                sync = .failed
            } else {
                cueCache[url] = cues
                sync = .ready(url: url, cues: cues)
            }
        } catch {
            sync = .failed
        }
    }

    /// The viewer heard `cue` right now: shift subtitles so it shows at this moment.
    func syncSubtitle(to cue: SubtitleCue) {
        setSubtitleDelay(((precisePosition - cue.start) * 100).rounded() / 100)
    }

    // MARK: Controls

    func togglePlay() {
        handle?.setFlag("pause", !isPaused)
    }

    func skip(_ seconds: Double) {
        handle?.command(["seek", String(seconds), "relative"])
        position = min(max(position + seconds, 0), duration)
    }

    func commitScrub() {
        handle?.command(["seek", String(scrubPosition), "absolute"])
        position = scrubPosition
        isScrubbing = false
        saveProgress()
    }

    func setSpeed(_ value: Double) {
        speed = value
        handle?.setDouble("speed", value)
    }

    func selectAudio(_ track: MPVTrack) {
        handle?.setString("aid", String(track.id))
        refreshTracks()
    }

    func selectSubtitle(_ track: MPVTrack?) {
        handle?.setString("sid", track.map { String($0.id) } ?? "no")
        refreshTracks()
    }

    func playNextEpisode() async {
        guard let next = session.next, let context, !isLoadingNext else { return }
        isLoadingNext = true
        defer { isLoadingNext = false }
        saveProgress()
        guard let nextSession = await launcher.session(for: next, after: session, context: context) else {
            errorMessage = localized("No playable stream was found for the next episode.")
            return
        }
        session = nextSession
        errorMessage = nil
        load(nextSession)
    }

    // MARK: Progress

    func saveProgress() {
        guard let context, duration > 0, position > 0 else { return }
        lastSavedPosition = position
        PlaybackProgressStore.save(
            metaID: session.metaID, type: session.type, videoID: session.videoID,
            position: position, duration: duration, in: context
        )
    }

    // MARK: Helpers

    static func threeLetterCode(_ code: String) -> String {
        ["ar": "ara", "en": "eng"][code] ?? code
    }

    static func languageName(_ code: String?) -> String? {
        guard let code else { return nil }
        return AppLanguage.current.locale.localizedString(forLanguageCode: code)
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
