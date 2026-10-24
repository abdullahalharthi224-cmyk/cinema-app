import UIKit

/// What the player screen needs from a video engine. Both engines report the
/// same events and tracks, so the controls look and behave identically.
@MainActor
protocol VideoEngine: AnyObject {
    var kind: PlayerEngineKind { get }
    /// Called on the main thread.
    var onEvent: ((PlayerEvent) -> Void)? { get set }

    /// Whether the engine draws addon subtitles itself. When it doesn't, the
    /// player screen draws them over the video.
    var drawsExternalSubtitles: Bool { get }
    var supportsPictureInPicture: Bool { get }
    var isPictureInPictureActive: Bool { get }

    func load(url: URL, start: Double)
    func setPaused(_ paused: Bool)
    func seek(to seconds: Double)
    func seek(by seconds: Double)
    func setSpeed(_ speed: Double)

    func fetchTracks(_ completion: @escaping ([PlayerTrack]) -> Void)
    func selectAudio(id: Int)
    /// `nil` turns subtitles off.
    func selectSubtitle(id: Int?)
    func addExternalSubtitle(url: String, title: String, language: String?)
    func setSubtitleDelay(_ seconds: Double)
    func setSubtitleFontSize(_ size: Int)
    func setSubtitleMargin(_ margin: Int)
    /// Text colour (`#RRGGBB`) and, if any, a box behind the lines (`#AARRGGBB`).
    func setSubtitleStyle(colorHex: String, backgroundColor: String?)

    /// Fill the screen (cropping the edges) or fit the whole picture.
    func setVideoFill(_ fill: Bool)
    /// The picture can't be drawn while the app is in the background.
    func setVideoEnabled(_ enabled: Bool)
    func togglePictureInPicture()
    /// A small preview frame for the timeline, when the engine can make one.
    func thumbnail(at seconds: Double) async -> UIImage?

    func destroy()
}
