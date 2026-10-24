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
    var isScrubbing = false
    var scrubPosition: Double = 0

    private var handle: MPVHandle?
    private var lastSavedPosition: Double = 0
    private var addedSubtitles = false
    private weak var context: ModelContext?
    private let launcher: PlaybackLauncher

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

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        UIApplication.shared.isIdleTimerDisabled = true

        load(session)
    }

    private func load(_ session: PlaybackSession) {
        hasLoaded = false
        isBuffering = true
        addedSubtitles = false
        position = session.startPosition
        duration = 0
        lastSavedPosition = session.startPosition
        handle?.setString("start", session.startPosition > 0 ? String(Int(session.startPosition)) : "none")
        handle?.command(["loadfile", session.url.absoluteString, "replace"])
        handle?.setFlag("pause", false)
    }

    func close() {
        saveProgress()
        handle?.destroy()
        handle = nil
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Events

    private func process(_ event: MPVEvent) {
        switch event {
        case .position(let value):
            position = value
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
            refreshTracks()
            Task { await addExternalSubtitles() }
        case .tracksChanged:
            refreshTracks()
        case .loadFailed(let reason):
            errorMessage = localized("This stream couldn't be played (%@). Try another one.", reason)
        }
    }

    private func refreshTracks() {
        let tracks = handle?.tracks() ?? []
        audioTracks = tracks.filter { $0.kind == .audio }
        subtitleTracks = tracks.filter { $0.kind == .sub }
    }

    /// Adds subtitles from subtitle addons (e.g. OpenSubtitles), preferred language first,
    /// and turns on the best one if the file has none in that language.
    private func addExternalSubtitles() async {
        guard !addedSubtitles, let context else { return }
        addedSubtitles = true
        let languages = PlaybackSettings.shared.subtitleLanguages
        let addons = PlaybackLauncher.enabledAddons(in: context)
        let items = await ContentService().subtitles(
            type: session.type, id: session.videoID, addons: addons, preferredLanguages: languages
        )
        guard handle != nil, !items.isEmpty else { return }

        // A few per language keeps the menu tidy.
        var perLanguage: [String: Int] = [:]
        let picked = items.filter { item in
            let code = SubtitleLanguage.code(for: item.lang) ?? "other"
            perLanguage[code, default: 0] += 1
            return perLanguage[code]! <= 3
        }

        let embeddedPreferred = subtitleTracks.contains { track in
            guard let first = languages.first else { return false }
            return SubtitleLanguage.code(for: track.language) == first && track.isSelected
        }
        for (index, item) in picked.prefix(12).enumerated() {
            let code = SubtitleLanguage.code(for: item.lang)
            let name = Self.languageName(code) ?? item.lang ?? localized("Subtitles")
            let shouldSelect = index == 0 && !embeddedPreferred && code == languages.first
            handle?.command(["sub-add", item.url, shouldSelect ? "select" : "auto", name, code ?? ""])
        }
        refreshTracks()
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
