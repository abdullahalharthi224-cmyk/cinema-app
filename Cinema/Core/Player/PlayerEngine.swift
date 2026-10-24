import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Something that happened in the player, delivered on the main thread.
enum PlayerEvent {
    case position(Double)
    case duration(Double)
    case paused(Bool)
    case buffering(Bool)
    case endReached(Bool)
    case fileLoaded
    case tracksChanged
    case loadFailed(String)
    case pictureInPicture(Bool)
}

/// One audio, subtitle or video track of the playing file.
struct PlayerTrack: Identifiable, Hashable {
    enum Kind: String { case audio, sub, video }

    var id: Int
    var kind: Kind
    var title: String?
    var language: String?
    var codec: String?
    var isSelected: Bool
    var isExternal: Bool
    /// For subtitles added from an addon: the URL they were loaded from.
    var externalFilename: String?
}

/// Which video engine plays a stream.
enum PlayerEngineKind: String, Hashable, Sendable {
    /// Apple's player: Picture in Picture, AirPlay video and HDR, but only for
    /// the formats iOS plays itself (MP4, MOV, HLS).
    case apple
    /// libmpv: plays everything (MKV, HEVC, multiple audio tracks, embedded subtitles).
    case mpv

    /// A decision from the file name alone, when it's conclusive.
    static func preferred(forPathExtension pathExtension: String) -> PlayerEngineKind? {
        switch pathExtension.lowercased() {
        case "mp4", "m4v", "mov", "m3u8": return .apple
        case "mkv", "avi", "webm", "ts", "m2ts", "flv", "wmv", "mpg", "mpeg", "ogv": return .mpv
        default: return nil
        }
    }

    /// A decision from the server's `Content-Type`, when it's conclusive.
    static func preferred(forContentType contentType: String) -> PlayerEngineKind? {
        let type = contentType.lowercased().split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        switch type {
        case "video/mp4", "video/quicktime", "video/x-m4v",
             "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "audio/x-mpegurl":
            return .apple
        case "video/x-matroska", "video/webm", "video/x-msvideo", "video/mp2t", "video/x-flv":
            return .mpv
        default:
            return nil
        }
    }

    /// Picks the engine for a stream. When the address doesn't say what the file
    /// is, the server is asked (briefly); anything uncertain goes to libmpv,
    /// which can play it all.
    static func choose(for url: URL, allowApple: Bool, http: HTTPClient = URLSessionHTTPClient()) async -> PlayerEngineKind {
        guard allowApple else { return .mpv }
        if let kind = preferred(forPathExtension: url.pathExtension) { return kind }

        var request = URLRequest(url: url, timeoutInterval: 2.5)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await http.send(request) else { return .mpv }
        if let contentType = response.value(forHTTPHeaderField: "Content-Type"),
           let kind = preferred(forContentType: contentType) {
            return kind
        }
        // Redirects often land on a URL that names the file.
        if let final = response.url, let kind = preferred(forPathExtension: final.pathExtension) { return kind }
        return .mpv
    }
}
