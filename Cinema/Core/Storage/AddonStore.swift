import Foundation
import SwiftData
import SwiftUI

struct StremioImportSummary: Equatable {
    var added = 0
    var updated = 0
    /// Addons that only work with the desktop Stremio streaming server.
    var skipped = 0

    var imported: Int { added + updated }
}

enum StremioDefaults {
    /// The signed-in account's email, kept only for display. Non-empty means connected.
    static let emailKey = "stremio.email"
}

/// All the operations the app performs on installed addons.
/// Views create one on demand with their `ModelContext`.
@MainActor
struct AddonStore {
    let context: ModelContext
    var client = AddonClient()
    var account = StremioAccountClient()
    var keychain = KeychainStore()
    var defaults: UserDefaults = .standard

    func allAddons() throws -> [InstalledAddon] {
        try context.fetch(FetchDescriptor<InstalledAddon>(sortBy: [SortDescriptor(\.sortIndex)]))
    }

    // MARK: Manual install

    /// Fetches the manifest for whatever the user pasted, without installing it yet.
    func previewManifest(for input: String) async throws -> (url: URL, manifest: AddonManifest) {
        let url = try AddonURL.normalizedManifestURL(from: input)
        let manifest = try await client.manifest(at: url)
        return (url, manifest)
    }

    @discardableResult
    func install(manifest: AddonManifest, from url: URL) throws -> InstalledAddon {
        let all = try allAddons()
        if let existing = all.first(where: { $0.transportUrl == url.absoluteString }) {
            existing.update(manifest: manifest)
            existing.isEnabled = true
            try context.save()
            return existing
        }
        let addon = InstalledAddon(
            manifestURL: url, manifest: manifest, source: .manual,
            sortIndex: (all.map(\.sortIndex).max() ?? -1) + 1
        )
        context.insert(addon)
        try context.save()
        return addon
    }

    func refreshManifest(of addon: InstalledAddon) async throws {
        guard let url = addon.manifestURL else { throw AddonError.invalidURL(addon.transportUrl) }
        let manifest = try await client.manifest(at: url)
        addon.update(manifest: manifest)
        try context.save()
    }

    // MARK: Stremio account

    var isStremioConnected: Bool { keychain.string(for: KeychainKey.stremioAuthKey) != nil }

    /// Signs in, keeps only the auth key (never the password) and imports the addon collection.
    func importFromStremio(email: String, password: String) async throws -> StremioImportSummary {
        let session = try await account.login(email: email, password: password)
        keychain.set(session.authKey, for: KeychainKey.stremioAuthKey)
        defaults.set(session.email ?? email, forKey: StremioDefaults.emailKey)
        return try await sync(authKey: session.authKey)
    }

    func resyncStremio() async throws -> StremioImportSummary {
        guard let authKey = keychain.string(for: KeychainKey.stremioAuthKey) else {
            signOutOfStremio()
            throw StremioAccountError.sessionExpired
        }
        do {
            return try await sync(authKey: authKey)
        } catch StremioAccountError.sessionExpired {
            signOutOfStremio()
            throw StremioAccountError.sessionExpired
        }
    }

    /// Forgets the Stremio session. Imported addons stay installed.
    func signOutOfStremio() {
        keychain.remove(KeychainKey.stremioAuthKey)
        defaults.removeObject(forKey: StremioDefaults.emailKey)
    }

    private func sync(authKey: String) async throws -> StremioImportSummary {
        let descriptors = try await account.addonCollection(authKey: authKey)

        var existing = Dictionary(
            try allAddons().map { ($0.transportUrl, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var nextIndex = (existing.values.map(\.sortIndex).max() ?? -1) + 1
        var summary = StremioImportSummary()

        for descriptor in descriptors {
            guard let url = try? AddonURL.normalizedManifestURL(from: descriptor.transportUrl),
                  !AddonURL.isLocalOnly(url)
            else {
                summary.skipped += 1
                continue
            }

            if let addon = existing[url.absoluteString] {
                // Keep the user's local order and on/off choice; refresh the manifest.
                addon.update(manifest: descriptor.manifest)
                summary.updated += 1
            } else {
                let addon = InstalledAddon(
                    manifestURL: url, manifest: descriptor.manifest, source: .stremio, sortIndex: nextIndex
                )
                context.insert(addon)
                existing[url.absoluteString] = addon
                nextIndex += 1
                summary.added += 1
            }
        }

        try context.save()
        return summary
    }

    // MARK: Organising

    func move(_ addons: [InstalledAddon], fromOffsets source: IndexSet, toOffset destination: Int) throws {
        var reordered = addons
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, addon) in reordered.enumerated() where addon.sortIndex != index {
            addon.sortIndex = index
        }
        try context.save()
    }

    func remove(_ addons: [InstalledAddon]) throws {
        for addon in addons {
            context.delete(addon)
        }
        try context.save()
    }

    func setEnabled(_ addon: InstalledAddon, _ isEnabled: Bool) throws {
        addon.isEnabled = isEnabled
        try context.save()
    }
}
