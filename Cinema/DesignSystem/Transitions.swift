import SwiftUI

// MARK: - Zoom transitions

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The namespace that connects a poster to the detail page it opens.
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Marks this view as the origin of a zoom transition (iOS 18+; a normal push before that).
    @ViewBuilder
    func zoomSource(id: String?, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let id, let namespace {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(.continuous(Theme.Radius.poster))
            }
        } else {
            self
        }
    }

    /// Makes a pushed screen grow out of its matching `zoomSource`.
    @ViewBuilder
    func zoomDestination(id: String?, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let id, let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

// MARK: - Artwork

/// Artwork URLs, falling back to Stremio's public image service for IMDb titles
/// when an addon doesn't provide them.
enum Artwork {
    private static let metahub = "https://images.metahub.space"

    static func logo(id: String, provided: String?) -> URL? {
        if let url = provided?.asURL { return url }
        return imdbID(id).flatMap { URL(string: "\(metahub)/logo/medium/\($0)/img") }
    }

    static func background(id: String, provided: String?) -> URL? {
        if let url = provided?.asURL { return url }
        return imdbID(id).flatMap { URL(string: "\(metahub)/background/medium/\($0)/img") }
    }

    private static func imdbID(_ id: String) -> String? {
        let base = id.split(separator: ":").first.map(String.init) ?? id
        return base.hasPrefix("tt") ? base : nil
    }
}
