import Foundation

/// A thread-safe snapshot of an enabled addon, used by the content services.
/// (`InstalledAddon` is a SwiftData model and must stay on the main actor.)
struct AddonSource: Sendable, Hashable, Identifiable {
    /// The manifest URL, which uniquely identifies an installed addon.
    var id: String
    var name: String
    var baseURL: URL
    var manifest: AddonManifest

    init(id: String, name: String, baseURL: URL, manifest: AddonManifest) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.manifest = manifest
    }

    init(manifestURL: URL, manifest: AddonManifest) {
        self.init(
            id: manifestURL.absoluteString,
            name: manifest.name,
            baseURL: AddonURL.configuredBaseURL(
                AddonURL.baseURL(fromManifestURL: manifestURL),
                manifestID: manifest.id,
                language: AppLanguage.current.tmdbCode
            ),
            manifest: manifest
        )
    }

    func supports(_ resource: AddonResource, type: String, id: String? = nil) -> Bool {
        manifest.supports(resource: resource.rawValue, type: type, id: id)
    }

    /// Catalogs that can be shown as rows without any user input.
    var browsableCatalogs: [CatalogReference] {
        manifest.catalogs.filter(\.isBrowsable).map { CatalogReference(addon: self, catalog: $0) }
    }

    var searchableCatalogs: [CatalogReference] {
        manifest.searchableCatalogs.map { CatalogReference(addon: self, catalog: $0) }
    }
}

/// One catalog of one addon, e.g. "Cinemeta → Popular Movies".
struct CatalogReference: Sendable, Hashable, Identifiable {
    var addon: AddonSource
    var catalog: CatalogDescriptor

    var id: String { addon.id + "|" + catalog.identity }
    var type: String { catalog.type }
}
