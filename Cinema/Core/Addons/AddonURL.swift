import Foundation

/// Helpers for turning whatever the user pastes into a canonical manifest URL,
/// and for deriving an addon's base URL from it.
enum AddonURL {
    static let manifestFileName = "manifest.json"

    /// Accepts `https://…/manifest.json`, `stremio://…/manifest.json`,
    /// URLs without the `manifest.json` suffix and URLs without a scheme.
    static func normalizedManifestURL(from input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AddonError.invalidURL(input) }

        if let replacement = modernReplacement(for: text) {
            return replacement
        }

        if text.lowercased().hasPrefix("stremio://") {
            text = "https://" + text.dropFirst("stremio://".count)
        } else if !text.contains("://") {
            text = "https://" + text
        }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty
        else {
            throw AddonError.invalidURL(input)
        }

        components.scheme = scheme
        var path = components.path
        // Old-protocol addons have no manifest.json; keep their address as it is.
        if !isLegacyPath(path), !path.hasSuffix("/" + manifestFileName) {
            while path.hasSuffix("/") { path.removeLast() }
            path += "/" + manifestFileName
        }
        components.path = path
        components.fragment = nil

        guard let url = components.url else { throw AddonError.invalidURL(input) }
        return url
    }

    /// `https://host/config/manifest.json` → `https://host/config`
    static func baseURL(fromManifestURL manifestURL: URL) -> URL {
        var components = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false)
        var path = components?.path ?? ""
        if path.hasSuffix("/" + manifestFileName) {
            path.removeLast(manifestFileName.count + 1)
        }
        components?.path = path
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? manifestURL
    }

    /// Percent-encodes a value like JavaScript's `encodeURIComponent`, which is
    /// what Stremio clients use when building resource paths.
    static func encodeComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: uriComponentAllowed) ?? value
    }

    private static let uriComponentAllowed: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'()")
        return set
    }()

    /// Addons built for Stremio's retired v1 protocol ("…/stremio/v1"), which
    /// this app (like modern Stremio) can't talk to.
    static func isLegacy(_ url: URL) -> Bool {
        isLegacyPath(url.path)
    }

    private static func isLegacyPath(_ path: String) -> Bool {
        path.contains("/stremio/v1")
    }

    /// Official addons whose old-protocol address has a modern equivalent.
    private static let replacements: [(host: String, manifest: String)] = [
        ("opensubtitles.strem.io", "https://opensubtitles-v3.strem.io/manifest.json"),
    ]

    /// The modern address for a known legacy addon, if there is one.
    static func modernReplacement(for text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(),
              isLegacyPath(url.path)
        else { return nil }
        return replacements.first { $0.host == host }.flatMap { URL(string: $0.manifest) }
    }

    /// Addons that only work with the desktop Stremio streaming server.
    static func isLocalOnly(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }
}
