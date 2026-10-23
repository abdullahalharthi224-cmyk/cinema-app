import Foundation
import SwiftData

/// An addon the user has installed, persisted with SwiftData.
@Model
final class InstalledAddon {
    /// The manifest URL is what uniquely identifies an installed addon:
    /// the same addon can be installed twice with different configurations.
    @Attribute(.unique) var transportUrl: String
    var addonID: String
    var name: String
    var manifestData: Data
    var isEnabled: Bool
    var sortIndex: Int
    var sourceRaw: String
    var addedAt: Date
    var updatedAt: Date

    init(manifestURL: URL, manifest: AddonManifest, source: Source, sortIndex: Int, isEnabled: Bool = true) {
        transportUrl = manifestURL.absoluteString
        addonID = manifest.id
        name = manifest.name
        manifestData = (try? JSONEncoder.addon.encode(manifest)) ?? Data()
        self.isEnabled = isEnabled
        self.sortIndex = sortIndex
        sourceRaw = source.rawValue
        addedAt = .now
        updatedAt = .now
    }

    enum Source: String {
        case stremio
        case manual
    }

    var source: Source { Source(rawValue: sourceRaw) ?? .manual }

    var manifest: AddonManifest? {
        try? JSONDecoder.addon.decode(AddonManifest.self, from: manifestData)
    }

    var manifestURL: URL? { URL(string: transportUrl) }

    var baseURL: URL? { manifestURL.map(AddonURL.baseURL(fromManifestURL:)) }

    func update(manifest: AddonManifest) {
        addonID = manifest.id
        name = manifest.name
        if let data = try? JSONEncoder.addon.encode(manifest) {
            manifestData = data
        }
        updatedAt = .now
    }
}

extension InstalledAddon {
    /// A thread-safe copy for the content services, or `nil` if the stored data is unreadable.
    var snapshot: AddonSource? {
        guard let manifestURL, let manifest else { return nil }
        return AddonSource(manifestURL: manifestURL, manifest: manifest)
    }
}

extension Array where Element == InstalledAddon {
    var sources: [AddonSource] { compactMap(\.snapshot) }
}
