import AVFoundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class PlayerViewModel {
    private(set) var session: PlaybackSession
    /// Which engine is playing. Switches to libmpv if Apple's player can't open a stream.
    private(set) var engineKind: PlayerEngineKind
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPaused = false
    private(set) var isBuffering = true
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var audioTracks: [PlayerTrack] = []
    private(set) var subtitleTracks: [PlayerTrack] = []
    private(set) var speed: Double = 1
    private(set) var isLoadingNext = false
    private(set) var subtitleSources: [SubtitleSource] = []
    private(set) var isLoadingSubtitles = false
    private(set) var subtitleDelay: Double = 0 {
        didSet { refreshOverlayText() }
    }
    private(set) var subtitleRaise: Double = 40
    private(set) var sync: SyncState = .idle
    private(set) var supportsPictureInPicture = false
    private(set) var isPictureInPictureActive = false
    private(set) var videoFill = false
    private(set) var scrubThumbnail: UIImage?
    /// Addon subtitles the player screen draws itself (Apple's player).
    private(set) var overlayCues: [SubtitleCue]? {
        didSet { refreshOverlayText() }
    }
    /// The subtitle line drawn right now. Only changes when the line does, so the
    /// player screen isn't redrawn on every video frame.
    private(set) var overlayText: String?
    /// The playback time for drawn subtitles, updated ten times a second.
    @ObservationIgnored private var subtitleClock: Double = 0
    /// Intro, recap and end-credits timings (from IntroDB).
    private(set) var segments: MediaSegments = .none
    /// A short message over the picture ("Skipped intro", "Trying another link…").
    private(set) var notice: Notice?
    /// Seconds left before the next episode starts by itself.
    private(set) var nextCountdown: Int?
    private(set) var countdownCancelled = false
    /// "More Like This" at the end of a movie.
    private(set) var suggestions: [TMDBTitle] = []
    private(set) var suggestionsDismissed = false
    /// The sleep timer, if one is set.
    private(set) var sleepTimer: SleepTimer?
    /// Seconds until the sleep timer stops playback.
    private(set) var sleepRemaining: Int?
    private var controlsVisible = true
    var isScrubbing = false
    var scrubPosition: Double = 0

    @ObservationIgnored private var engine: VideoEngine?
    @ObservationIgnored private let nowPlaying = NowPlayingController()
    /// The exact playback time, without the UI throttling applied to `position`.
    @ObservationIgnored private var precisePosition: Double = 0
    @ObservationIgnored private var cueCache: [String: [SubtitleCue]] = [:]
    @ObservationIgnored private var lastSavedPosition: Double = 0
    /// Where watched time was last counted for the statistics.
    @ObservationIgnored private var lastLoggedPosition: Double = -1
    @ObservationIgnored private var sourcesLoaded = false
    @ObservationIgnored private var subtitlesDecided = false
    @ObservationIgnored private var userPickedSubtitle = false
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var overlayTask: Task<Void, Never>?
    @ObservationIgnored private var skippedSegments: Set<Double> = []
    @ObservationIgnored private var failedURLs: Set<URL> = []
    @ObservationIgnored private var isTryingAnother = false
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var loadTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var segmentsTask: Task<Void, Never>?
    @ObservationIgnored private var suggestionsTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var suggestionsMedia: TMDBMediaType = .movie
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var sleepDeadline: Date?
    @ObservationIgnored private var routeObserver: NSObjectProtocol?
    @ObservationIgnored private weak var context: ModelContext?
    @ObservationIgnored private let launcher: PlaybackLauncher

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

    enum Notice: Equatable {
        case skippedIntro, skippedRecap, tryingAnother, airPlayAudioOnly, sleepTimerSet
    }

    enum SleepTimer: Hashable {
        case minutes(Int)
        case endOfEpisode
    }

    enum SkipKind: Equatable { case intro, recap }

    static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    init(session: PlaybackSession, launcher: PlaybackLauncher) {
        self.session = session
        self.engineKind = session.engine
        self.launcher = launcher
    }

    var displayedPosition: Double { isScrubbing ? scrubPosition : position }
    var remaining: Double { max(duration - displayedPosition, 0) }

    /// Where the end credits begin: IntroDB's timing, otherwise 30 seconds
    /// before the end of an episode or two minutes before the end of a movie.
    var creditsStart: Double? {
        guard duration > 180 else { return nil }
        if let outro = segments.outro, outro.start < duration { return outro.start }
        return duration - (session.type == "movie" ? 120 : 30)
    }

    private var isInCredits: Bool {
        guard let creditsStart else { return false }
        return displayedPosition >= creditsStart
    }

    /// The "Next Episode" button, once the countdown was cancelled or is turned off.
    var showsNextEpisode: Bool {
        session.next != nil && isInCredits && nextCountdown == nil
    }

    /// "More Like This" over a movie's end credits.
    var showsSuggestions: Bool {
        session.next == nil && session.type == "movie" && isInCredits && !suggestions.isEmpty && !suggestionsDismissed
    }

    /// The intro or recap playing right now, offered as "Skip Intro".
    var activeSkip: SkipKind? {
        activeSkipSpan(at: displayedPosition)?.kind
    }

    private func activeSkipSpan(at time: Double) -> (kind: SkipKind, span: MediaSegments.Span)? {
        if let recap = segments.recap, recap.contains(time), recap.end - time > 1 { return (.recap, recap) }
        if let intro = segments.intro, intro.contains(time), intro.end - time > 1 { return (.intro, intro) }
        return nil
    }

    // MARK: Lifecycle

    /// Called once the video surface for `engineKind` is on screen.
    func attach(to controller: UIViewController, context: ModelContext) {
        guard engine == nil else { return }
        self.context = context

        let engine: VideoEngine?
        if let controller = controller as? AVVideoViewController {
            engine = AVPlayerEngine(controller: controller)
        } else if let controller = controller as? MPVVideoViewController {
            engine = MPVEngine(controller: controller, options: mpvOptions())
        } else {
            engine = nil
        }
        guard let engine else {
            errorMessage = localized("The player couldn't start.")
            return
        }
        engine.onEvent = { [weak self] event in self?.process(event) }
        self.engine = engine
        supportsPictureInPicture = engine.supportsPictureInPicture
        engine.setVideoFill(videoFill)

        if lifecycleObservers.isEmpty {
            observeAppLifecycle()
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
            try? AVAudioSession.sharedInstance().setActive(true)
            UIApplication.shared.isIdleTimerDisabled = true
            activateNowPlaying()
            observeAudioRoute()
        }
        load(session)
    }

    /// AirPlay carries the picture only from Apple's player; with the built-in
    /// one, the TV gets the sound. Say so when the viewer picks AirPlay.
    private func observeAudioRoute() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.engineKind == .mpv else { return }
                let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
                if outputs.contains(where: { $0.portType == .airPlay }) {
                    self.show(.airPlayAudioOnly, for: 6)
                }
            }
        }
    }

    /// Subtitles in the preferred language only: libmpv must never pick another
    /// language on its own (the view model handles the fallback).
    private func mpvOptions() -> [String: String] {
        var options: [String: String] = [:]
        let settings = PlaybackSettings.shared
        options["sub-font-size"] = String(settings.subtitleSize.fontSize)
        options["sub-color"] = settings.subtitleColorHex
        if settings.subtitleBackground > 0.01 {
            options["sub-border-style"] = "background-box"
            options["sub-back-color"] = settings.subtitleBackgroundMPVColor
        }
        if settings.audioPreference == .arabic {
            options["alang"] = "ar,ara"
        }
        if settings.needsAudioProcessing {
            options.merge(settings.audioProcessing) { $1 }
        }
        if let language = PlaybackSettings.shared.preferredSubtitleLanguage {
            options["slang"] = "\(language),\(Self.threeLetterCode(language))"
        } else {
            options["sid"] = "no"
        }
        return options
    }

    private func load(_ session: PlaybackSession) {
        hasLoaded = false
        isBuffering = true
        subtitlesDecided = false
        userPickedSubtitle = false
        sourcesLoaded = session.subtitleSources != nil
        subtitleSources = session.subtitleSources ?? []
        subtitleDelay = 0
        overlayCues = nil
        sync = .idle
        position = session.startPosition
        precisePosition = session.startPosition
        duration = 0
        lastSavedPosition = session.startPosition
        lastLoggedPosition = -1
        segments = .none
        skippedSegments = []
        nextCountdown = nil
        countdownCancelled = false
        countdownTask?.cancel()
        suggestions = []
        suggestionsDismissed = false
        suggestionsTask = nil
        engine?.load(url: session.url, start: session.startPosition)
        engine?.setSpeed(speed)
        loadSegments(for: session)
        watchForStall()
    }

    /// Starts `session` in the right engine: the current one, or a fresh surface
    /// (and engine) when the new link needs the other one.
    private func start(_ session: PlaybackSession) {
        self.session = session
        if session.engine != engineKind {
            engine?.destroy()
            engine = nil
            hasLoaded = false
            engineKind = session.engine
        } else {
            load(session)
        }
    }

    private func loadSegments(for session: PlaybackSession) {
        segmentsTask?.cancel()
        // Timings saved with a download work offline.
        let saved = DownloadManager.shared.item(videoID: session.videoID)?.segments
        if let saved, saved != .none {
            segments = saved
            return
        }
        guard let reference = IntroDBClient.reference(videoID: session.videoID) else { return }
        segmentsTask = Task {
            let found = try? await IntroDBClient().segments(
                imdbID: reference.imdbID, season: reference.season, episode: reference.episode
            )
            guard !Task.isCancelled, self.session.videoID == session.videoID else { return }
            segments = found ?? .none
        }
    }

    /// A link that never starts is treated like one that failed.
    private func watchForStall() {
        loadTimeoutTask?.cancel()
        loadTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, !hasLoaded, errorMessage == nil else { return }
            await tryAnotherStream(reason: localized("it took too long to start"))
        }
    }

    func close() {
        countdownTask?.cancel()
        sleepTask?.cancel()
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        loadTimeoutTask?.cancel()
        segmentsTask?.cancel()
        suggestionsTask?.cancel()
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycleObservers = []
        saveProgress()
        thumbnailTask?.cancel()
        overlayTask?.cancel()
        nowPlaying.deactivate()
        engine?.destroy()
        engine = nil
        // "Delete episodes after watching", for downloads.
        if let context, PlaybackProgressStore.progress(videoID: session.videoID, in: context)?.watched == true {
            DownloadManager.shared.deleteIfWatched(videoID: session.videoID)
        }
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Keeps playing in the background: in Picture in Picture when it's open,
    /// otherwise as sound only (with Lock Screen controls). The picture comes
    /// back on return.
    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let engine = self.engine else { return }
                    self.saveProgress()
                    self.updateNowPlaying()
                    guard !engine.isPictureInPictureActive else { return }
                    engine.setVideoEnabled(false)
                }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let engine = self.engine, !engine.isPictureInPictureActive else { return }
                    engine.setVideoEnabled(true)
                }
            },
        ]
    }

    /// Apple's player couldn't open the stream: hand it to libmpv instead. The
    /// player screen swaps the video surface and calls `attach` again.
    private func switchToMPV() {
        loadTimeoutTask?.cancel()
        engine?.destroy()
        engine = nil
        hasLoaded = false
        errorMessage = nil
        session.startPosition = max(position, session.startPosition)
        engineKind = .mpv
    }

    // MARK: Lock Screen

    private func activateNowPlaying() {
        nowPlaying.activate(
            title: session.title, subtitle: session.subtitle, artwork: session.artwork,
            actions: .init(
                setPaused: { [weak self] paused in self?.engine?.setPaused(paused) },
                togglePlay: { [weak self] in self?.togglePlay() },
                skip: { [weak self] seconds in self?.skip(seconds) },
                seek: { [weak self] seconds in self?.seek(to: seconds) }
            )
        )
    }

    private func updateNowPlaying() {
        nowPlaying.update(position: precisePosition, duration: duration, rate: isPaused ? 0 : speed)
    }

    // MARK: Picture

    /// Lifts subtitles above the controls while they're on screen.
    func controlsVisibilityChanged(_ visible: Bool) {
        controlsVisible = visible
        applySubtitleMargin()
    }

    /// The bottom margin of subtitles, in libmpv's units (pixels of a 720-line picture).
    var subtitleMargin: Double { subtitleRaise + (controlsVisible ? 110 : 0) }

    private func applySubtitleMargin() {
        engine?.setSubtitleMargin(Int(subtitleMargin))
    }

    func setSubtitleSize(_ size: PlaybackSettings.SubtitleSize) {
        PlaybackSettings.shared.subtitleSize = size
        engine?.setSubtitleFontSize(size.fontSize)
    }

    /// Positive shows subtitles later, negative earlier (seconds).
    func adjustSubtitleDelay(by step: Double) {
        setSubtitleDelay(((subtitleDelay + step) * 100).rounded() / 100)
    }

    func setSubtitleDelay(_ seconds: Double) {
        subtitleDelay = seconds
        engine?.setSubtitleDelay(seconds)
    }

    /// How high subtitles sit above the bottom of the picture.
    func setSubtitleRaise(_ value: Double) {
        subtitleRaise = value
        applySubtitleMargin()
    }

    /// Pinch out to fill the screen, pinch in to see the whole picture.
    func setVideoFill(_ fill: Bool) {
        guard fill != videoFill else { return }
        videoFill = fill
        engine?.setVideoFill(fill)
    }

    func togglePictureInPicture() {
        engine?.togglePictureInPicture()
    }

    // MARK: Events

    private func process(_ event: PlayerEvent) {
        switch event {
        case .position(let value):
            precisePosition = value
            if overlayCues != nil {
                subtitleClock = value
                refreshOverlayText()
            }
            followTimeline(value)
            // Updates arrive many times a second; a few a second is plenty for the UI.
            if abs(value - position) >= 0.25 || value < position { position = value }
            if abs(value - lastSavedPosition) >= 10 {
                saveProgress()
                updateNowPlaying()
            }
        case .duration(let value):
            duration = value
            updateNowPlaying()
        case .paused(let paused):
            guard paused != isPaused else { return }
            isPaused = paused
            if paused { saveProgress() }
            updateNowPlaying()
        case .buffering(let buffering):
            isBuffering = buffering
        case .endReached(let ended):
            if ended {
                saveProgress()
                isPaused = true
                updateNowPlaying()
            }
        case .fileLoaded:
            hasLoaded = true
            isBuffering = false
            loadTimeoutTask?.cancel()
            applySubtitleMargin()
            refreshTracks { [weak self] in
                guard let self else { return }
                self.applyAudioPreference()
                self.decideSubtitles()
                if !self.sourcesLoaded {
                    Task { await self.loadSubtitleSources() }
                }
            }
        case .tracksChanged:
            refreshTracks()
        case .pictureInPicture(let active):
            isPictureInPictureActive = active
        case .loadFailed(let reason):
            if engineKind == .apple && !hasLoaded {
                switchToMPV()
            } else {
                Task { await tryAnotherStream(reason: reason) }
            }
        }
    }

    private func refreshTracks(then completion: (() -> Void)? = nil) {
        guard let engine else { return }
        engine.fetchTracks { [weak self] tracks in
            guard let self else { return }
            self.audioTracks = tracks.filter { $0.kind == .audio }
            self.subtitleTracks = tracks.filter { $0.kind == .sub }
            self.updateOverlay()
            completion?()
        }
    }

    // MARK: Subtitles

    /// Subtitles inside the video file.
    var embeddedSubtitles: [PlayerTrack] { subtitleTracks.filter { !$0.isExternal } }

    var isSubtitleOff: Bool { subtitleTracks.allSatisfy { !$0.isSelected } }

    /// The addon subtitle currently showing, by URL.
    var selectedSubtitleURL: String? {
        subtitleTracks.first { $0.isSelected && $0.isExternal }?.externalFilename
    }

    /// Chooses the subtitles to start with: the preferred language from the
    /// video, then from addons; failing that, the fallback language from
    /// Settings, or none. Never another language by accident.
    private func decideSubtitles() {
        guard !subtitlesDecided, !userPickedSubtitle else { return }
        let settings = PlaybackSettings.shared
        guard let preferred = settings.preferredSubtitleLanguage else {
            subtitlesDecided = true
            engine?.selectSubtitle(id: nil)
            return
        }
        if show(language: preferred) {
            subtitlesDecided = true
            return
        }
        // Still waiting for addons: keep whatever the engine picked out of the
        // way until we know whether there's one in the preferred language.
        guard sourcesLoaded else {
            if !isSubtitleOff { engine?.selectSubtitle(id: nil) }
            return
        }
        subtitlesDecided = true
        if let fallback = settings.fallbackSubtitleLanguage, show(language: fallback) { return }
        engine?.selectSubtitle(id: nil)
        refreshTracks()
    }

    /// Shows subtitles in `language`, from the video if it has them, otherwise
    /// from an addon. Returns whether any were found.
    private func show(language: String) -> Bool {
        if let track = embeddedSubtitles.first(where: { SubtitleLanguage.code(for: $0.language) == language }) {
            if !track.isSelected {
                engine?.selectSubtitle(id: track.id)
                refreshTracks()
            }
            return true
        }
        if let item = subtitleSources.lazy.flatMap(\.items).first(where: { SubtitleLanguage.code(for: $0.lang) == language }) {
            showExternal(item)
            return true
        }
        return false
    }

    /// Fetches what every subtitle addon offers, when it wasn't ready before playback.
    private func loadSubtitleSources() async {
        guard !sourcesLoaded, let context else { return }
        sourcesLoaded = true
        isLoadingSubtitles = true
        defer { isLoadingSubtitles = false }

        let languages = PlaybackSettings.shared.subtitleLanguages
        let sources = await ContentService().subtitleSources(
            type: session.type, id: session.videoID,
            addons: PlaybackLauncher.enabledAddons(in: context),
            preferredLanguages: languages.isEmpty ? ["ar", "en"] : languages
        )
        guard engine != nil else { return }
        subtitleSources = sources
        decideSubtitles()
    }

    /// Shows a subtitle from an addon (picked by the viewer).
    func selectExternalSubtitle(_ item: SubtitleItem) {
        userPickedSubtitle = true
        showExternal(item)
    }

    private func showExternal(_ item: SubtitleItem) {
        if let loaded = subtitleTracks.first(where: { $0.externalFilename == item.url }) {
            engine?.selectSubtitle(id: loaded.id)
        } else {
            let code = SubtitleLanguage.code(for: item.lang)
            let name = Self.languageName(code) ?? item.lang ?? localized("Subtitles")
            engine?.addExternalSubtitle(url: item.url, title: name, language: code)
        }
        refreshTracks()
    }

    /// With Apple's player, addon subtitles are drawn by the player screen.
    private func updateOverlay() {
        guard let engine, !engine.drawsExternalSubtitles else { return }
        guard let url = selectedSubtitleURL else {
            overlayTask?.cancel()
            overlayCues = nil
            return
        }
        overlayTask?.cancel()
        overlayTask = Task {
            let cues = await cues(for: url)
            guard !Task.isCancelled, selectedSubtitleURL == url else { return }
            subtitleClock = precisePosition
            overlayCues = cues
        }
    }

    private func refreshOverlayText() {
        var text: String?
        if let cues = overlayCues {
            let time = subtitleClock - subtitleDelay
            if let index = cues.activeIndex(at: time, tolerance: 0) {
                let cue = cues[index]
                text = cue.start <= time && time <= cue.end ? cue.text : nil
            }
        }
        if text != overlayText { overlayText = text }
    }

    /// Downloads and reads a subtitle file once, for drawing and for tap-to-sync.
    private func cues(for url: String) async -> [SubtitleCue]? {
        if let cached = cueCache[url] { return cached }
        guard let address = URL(string: url),
              let (data, _) = try? await URLSession.shared.data(from: address)
        else { return nil }
        let cues = await Task.detached { SubtitleParser.parse(data) }.value
        guard !cues.isEmpty else { return nil }
        cueCache[url] = cues
        return cues
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
        if cueCache[url] == nil { sync = .loading }
        let cues = await cues(for: url)
        guard selectedSubtitleURL == url else { return }
        if let cues {
            sync = .ready(url: url, cues: cues)
        } else {
            sync = .failed
        }
    }

    /// The viewer heard `cue` right now: shift subtitles so it shows at this moment.
    func syncSubtitle(to cue: SubtitleCue) {
        setSubtitleDelay(((precisePosition - cue.start) * 100).rounded() / 100)
    }

    // MARK: Controls

    func togglePlay() {
        engine?.setPaused(!isPaused)
    }

    func skip(_ seconds: Double) {
        engine?.seek(by: seconds)
        position = min(max(position + seconds, 0), duration)
        precisePosition = position
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        engine?.seek(to: seconds)
        position = seconds
        precisePosition = seconds
        updateNowPlaying()
    }

    func commitScrub() {
        seek(to: scrubPosition)
        isScrubbing = false
        thumbnailTask?.cancel()
        scrubThumbnail = nil
        saveProgress()
    }

    /// Fetches a preview frame for the timeline while scrubbing, if the engine can.
    /// The nearest frame already made shows at once; the exact one follows when
    /// the finger slows down (a little later for streams, to spare the connection).
    func requestThumbnail() {
        guard let engine else { return }
        thumbnailTask?.cancel()
        let time = scrubPosition
        if let nearby = engine.cachedThumbnail(near: time) { scrubThumbnail = nearby }
        let delay = engine.kind == .apple || session.url.isFileURL ? 120 : 250
        thumbnailTask = Task {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let image = await engine.thumbnail(at: time), !Task.isCancelled, isScrubbing else { return }
            scrubThumbnail = image
        }
    }

    func setSpeed(_ value: Double) {
        speed = value
        engine?.setSpeed(value)
        updateNowPlaying()
    }

    func selectAudio(_ track: PlayerTrack) {
        engine?.selectAudio(id: track.id)
        refreshTracks()
    }

    func selectSubtitle(_ track: PlayerTrack?) {
        userPickedSubtitle = true
        engine?.selectSubtitle(id: track?.id)
        refreshTracks()
    }

    func playNextEpisode() async {
        guard let next = session.next, let context, !isLoadingNext else { return }
        isLoadingNext = true
        defer { isLoadingNext = false }
        countdownTask?.cancel()
        nextCountdown = nil
        saveProgress()
        guard let nextSession = await launcher.session(for: next, after: session, context: context) else {
            errorMessage = localized("No playable stream was found for the next episode.")
            return
        }
        errorMessage = nil
        failedURLs = []
        start(nextSession)
        activateNowPlaying()
    }

    // MARK: Timeline: skip intro, end credits

    private func followTimeline(_ time: Double) {
        guard hasLoaded, !isScrubbing else { return }
        if PlaybackSettings.shared.autoSkipIntro,
           let skip = activeSkipSpan(at: time), !skippedSegments.contains(skip.span.start) {
            skippedSegments.insert(skip.span.start)
            seek(to: skip.span.end)
            show(skip.kind == .intro ? .skippedIntro : .skippedRecap)
            return
        }
        guard let creditsStart else { return }
        if time >= creditsStart {
            if session.next != nil, PlaybackSettings.shared.autoPlayNext, !countdownCancelled,
               nextCountdown == nil, !isLoadingNext, sleepTimer != .endOfEpisode {
                startCountdown()
            }
            // Suggestions aren't age-checked, so kids profiles don't get them.
            if session.next == nil, session.type == "movie", suggestionsTask == nil, !ProfileSession.shared.isKids {
                loadSuggestions()
            }
        } else if nextCountdown != nil {
            // Went back before the credits.
            countdownTask?.cancel()
            nextCountdown = nil
        }
    }

    /// Skips the intro or recap playing now.
    func skipSegment() {
        guard let skip = activeSkipSpan(at: precisePosition) else { return }
        skippedSegments.insert(skip.span.start)
        seek(to: skip.span.end)
    }

    private func startCountdown() {
        nextCountdown = 10
        countdownTask?.cancel()
        countdownTask = Task {
            while let remaining = nextCountdown, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                // Holds while paused.
                if !isPaused { nextCountdown = remaining - 1 }
            }
            guard !Task.isCancelled, nextCountdown != nil else { return }
            await playNextEpisode()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        nextCountdown = nil
        countdownCancelled = true
    }

    func playNextNow() {
        countdownTask?.cancel()
        Task { await playNextEpisode() }
    }

    private func loadSuggestions() {
        suggestionsTask = Task {
            guard let client = TMDBAccount.shared.client,
                  let imdbID = IntroDBClient.reference(videoID: session.videoID)?.imdbID,
                  let found = try? await client.find(imdbID: imdbID),
                  let details = try? await client.richDetails(
                      media: found.media, tmdbID: found.id, language: AppLanguage.current.tmdbCode
                  ),
                  !Task.isCancelled
            else { return }
            suggestionsMedia = found.media
            withAnimation(Theme.Motion.spring) {
                suggestions = Array(details.recommendations.filter { $0.posterPath != nil }.prefix(12))
            }
        }
    }

    func dismissSuggestions() {
        suggestionsDismissed = true
    }

    /// Opens a suggested title once the player has closed.
    func openSuggestion(_ title: TMDBTitle) {
        launcher.suggestedTitle = TMDBTitleRoute(media: suggestionsMedia, title: title)
    }

    // MARK: Failed links

    /// A link failed (or never started): quietly move on to the next best one.
    private func tryAnotherStream(reason: String) async {
        guard let context, !isTryingAnother else { return }
        failedURLs.insert(session.url)
        let fail = { self.errorMessage = localized("This stream couldn't be played (%@). Try another one.", reason) }
        guard failedURLs.count <= 5 else { return fail() }
        isTryingAnother = true
        show(.tryingAnother, for: nil)
        defer {
            isTryingAnother = false
            if notice == .tryingAnother { notice = nil }
        }
        let resumeAt = max(precisePosition, session.startPosition)
        guard let next = await launcher.alternativeSession(
            for: session, excluding: failedURLs, at: resumeAt, context: context
        ) else { return fail() }
        errorMessage = nil
        start(next)
    }

    private func show(_ notice: Notice, for seconds: Double? = 2.5) {
        noticeTask?.cancel()
        withAnimation(Theme.Motion.spring) { self.notice = notice }
        guard let seconds else { return }
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.spring) { self.notice = nil }
        }
    }

    // MARK: Sleep timer

    /// Stops playback after a while (or at the end of the episode), fading
    /// the sound out over the last 30 seconds.
    func setSleepTimer(_ timer: SleepTimer?) {
        sleepTask?.cancel()
        engine?.setVolume(1)
        sleepTimer = timer
        sleepRemaining = nil
        guard let timer else { return }
        if case .minutes(let minutes) = timer {
            sleepDeadline = Date.now.addingTimeInterval(Double(minutes * 60))
        }
        show(.sleepTimerSet)
        sleepTask = Task {
            while !Task.isCancelled {
                let remaining = secondsUntilSleep(timer)
                sleepRemaining = remaining.map { max(Int($0.rounded()), 0) }
                if let remaining {
                    if remaining <= 0 {
                        engine?.setPaused(true)
                        engine?.setVolume(1)
                        sleepTimer = nil
                        sleepRemaining = nil
                        return
                    }
                    engine?.setVolume(min(1, remaining / 30))
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func secondsUntilSleep(_ timer: SleepTimer) -> Double? {
        switch timer {
        case .minutes:
            // Counts real time while playing; paused time doesn't count.
            guard let deadline = sleepDeadline else { return nil }
            if isPaused { sleepDeadline = deadline.addingTimeInterval(1) }
            return deadline.timeIntervalSinceNow
        case .endOfEpisode:
            guard duration > 0 else { return nil }
            return (creditsStart ?? duration) - precisePosition
        }
    }

    // MARK: Night mode & dialogue boost

    func setNightMode(_ on: Bool) {
        PlaybackSettings.shared.nightMode = on
        applyAudioFilters()
    }

    func setDialogueBoost(_ on: Bool) {
        PlaybackSettings.shared.dialogueBoost = on
        applyAudioFilters()
    }

    /// Applies the filters; Apple's player can't process sound, so playback
    /// moves to the built-in player at the same moment.
    private func applyAudioFilters() {
        let settings = PlaybackSettings.shared
        if engineKind == .apple && settings.needsAudioProcessing {
            var moved = session
            moved.engine = .mpv
            moved.startPosition = max(precisePosition, 0)
            start(moved)
            return
        }
        engine?.setAudioProcessing(settings.audioProcessing)
    }

    // MARK: Audio & subtitle style

    /// Starts with Arabic dubbing when the viewer prefers it and the file has it.
    private func applyAudioPreference() {
        guard PlaybackSettings.shared.audioPreference == .arabic,
              let arabic = audioTracks.first(where: { SubtitleLanguage.code(for: $0.language) == "ar" }),
              !arabic.isSelected
        else { return }
        engine?.selectAudio(id: arabic.id)
        refreshTracks()
    }

    func setSubtitleColor(_ hex: String) {
        PlaybackSettings.shared.subtitleColorHex = hex
        applySubtitleStyle()
    }

    func setSubtitleBackground(_ opacity: Double) {
        PlaybackSettings.shared.subtitleBackground = opacity
        applySubtitleStyle()
    }

    private func applySubtitleStyle() {
        let settings = PlaybackSettings.shared
        engine?.setSubtitleStyle(
            colorHex: settings.subtitleColorHex,
            backgroundColor: settings.subtitleBackground > 0.01 ? settings.subtitleBackgroundMPVColor : nil
        )
    }

    // MARK: Progress

    func saveProgress() {
        guard let context, duration > 0, precisePosition > 0 else { return }
        lastSavedPosition = precisePosition
        logViewing(in: context)
        PlaybackProgressStore.save(
            metaID: session.metaID, type: session.type, videoID: session.videoID,
            position: precisePosition, duration: duration, in: context
        )
    }

    /// Counts the time watched since the last save (forward playback only;
    /// jumps and seeks back aren't counted) for the viewing statistics.
    private func logViewing(in context: ModelContext) {
        defer { lastLoggedPosition = precisePosition }
        guard lastLoggedPosition >= 0 else { return }
        let watched = precisePosition - lastLoggedPosition
        guard watched > 0, watched < 120 else { return }
        let entry = session.request.history
        ViewingLogStore.add(
            seconds: watched, metaID: session.metaID, type: session.type, videoID: session.videoID,
            name: entry?.name ?? session.title, poster: entry?.poster, background: entry?.background, in: context
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
