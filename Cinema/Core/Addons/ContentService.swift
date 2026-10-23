import Foundation

/// Streams returned by one addon, or the reason it couldn't provide any.
struct StreamGroup: Sendable, Identifiable {
    var addon: AddonSource
    var result: Result<[ParsedStream], AddonError>

    var id: String { addon.id }
}

/// A stream together with the details parsed out of its free-form text.
struct ParsedStream: Sendable, Hashable, Identifiable {
    var stream: StreamItem
    var info: StreamInfo
    /// Position within its addon's response, to keep identities stable.
    var index: Int
    var addonID: String

    var id: String { "\(addonID)#\(index)" }

    init(stream: StreamItem, index: Int, addonID: String) {
        self.stream = stream
        self.info = StreamInfo(stream: stream)
        self.index = index
        self.addonID = addonID
    }
}

/// Search results from one searchable catalog.
struct SearchSection: Sendable, Identifiable {
    var catalog: CatalogReference
    var items: [MetaPreview]

    var id: String { catalog.id }
}

/// High-level content operations across all enabled addons, following the
/// same rules the official Stremio clients use to decide which addon to ask.
struct ContentService: Sendable {
    var client: AddonClient

    init(client: AddonClient = AddonClient()) {
        self.client = client
    }

    func catalog(_ reference: CatalogReference, skip: Int = 0, genre: String? = nil) async throws -> [MetaPreview] {
        var extra: [ExtraArgument] = []
        if let genre, reference.catalog.supportsGenre { extra.append(.genre(genre)) }
        if skip > 0, reference.catalog.supportsSkip { extra.append(.skip(skip)) }
        return try await client.catalog(
            base: reference.addon.baseURL, type: reference.catalog.type, id: reference.catalog.id, extra: extra
        )
    }

    /// Asks addons for full details, starting with the one the item came from.
    func meta(type: String, id: String, preferredAddonID: String? = nil, addons: [AddonSource]) async throws -> MetaItem {
        let supporting = addons.filter { $0.supports(.meta, type: type, id: id) }
        let candidates = supporting.filter { $0.id == preferredAddonID }
            + supporting.filter { $0.id != preferredAddonID }

        var lastError: AddonError = .notFound
        for addon in candidates {
            do {
                return try await client.meta(base: addon.baseURL, type: type, id: id)
            } catch let error as AddonError {
                lastError = error
            }
        }
        throw lastError
    }

    /// Fetches streams from every addon that can provide them, in parallel,
    /// keeping the user's addon order. Each group reports its own errors.
    func streams(type: String, id: String, addons: [AddonSource]) async -> [StreamGroup] {
        let candidates = addons.filter { $0.supports(.stream, type: type, id: id) }

        return await withTaskGroup(of: (Int, StreamGroup).self) { group in
            for (offset, addon) in candidates.enumerated() {
                group.addTask {
                    do {
                        let streams = try await client.streams(base: addon.baseURL, type: type, id: id)
                        let parsed = streams.enumerated().map {
                            ParsedStream(stream: $0.element, index: $0.offset, addonID: addon.id)
                        }
                        return (offset, StreamGroup(addon: addon, result: .success(parsed)))
                    } catch {
                        return (offset, StreamGroup(addon: addon, result: .failure(Self.addonError(error))))
                    }
                }
            }
            var results: [(Int, StreamGroup)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Searches every catalog that supports search, in parallel.
    /// Throws only when every single addon failed.
    func search(_ query: String, addons: [AddonSource]) async throws -> [SearchSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let catalogs = addons.flatMap(\.searchableCatalogs)
        guard !catalogs.isEmpty else { return [] }

        let outcomes = await withTaskGroup(of: (Int, Result<[MetaPreview], AddonError>).self) { group in
            for (offset, reference) in catalogs.enumerated() {
                group.addTask {
                    do {
                        let items = try await client.catalog(
                            base: reference.addon.baseURL,
                            type: reference.catalog.type,
                            id: reference.catalog.id,
                            extra: [.search(trimmed)]
                        )
                        return (offset, .success(items))
                    } catch {
                        return (offset, .failure(Self.addonError(error)))
                    }
                }
            }
            var results: [(Int, Result<[MetaPreview], AddonError>)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }
        }

        var sections: [SearchSection] = []
        var firstError: AddonError?
        for (offset, outcome) in outcomes {
            switch outcome {
            case .success(let items) where !items.isEmpty:
                sections.append(SearchSection(catalog: catalogs[offset], items: items))
            case .success:
                break
            case .failure(let error):
                firstError = firstError ?? error
            }
        }
        if sections.isEmpty, let firstError, outcomes.allSatisfy({ if case .failure = $0.1 { true } else { false } }) {
            throw firstError
        }
        return sections
    }

    private static func addonError(_ error: Error) -> AddonError {
        (error as? AddonError) ?? .invalidResponse
    }
}
