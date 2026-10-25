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

    /// One page of a catalog. Recent pages come from memory unless `fresh` is set
    /// (pull to refresh), so going back and forth between screens is instant.
    func catalog(_ reference: CatalogReference, skip: Int = 0, genre: String? = nil, fresh: Bool = false) async throws -> [MetaPreview] {
        var extra: [ExtraArgument] = []
        if let genre, reference.catalog.supportsGenre { extra.append(.genre(genre)) }
        if skip > 0, reference.catalog.supportsSkip { extra.append(.skip(skip)) }
        let key = "\(reference.id)|\(skip)|\(genre ?? "")"
        if !fresh, let cached = await ResponseCache.catalogs.value(for: key, as: [MetaPreview].self) {
            return cached
        }
        let items = try await client.catalog(
            base: reference.addon.baseURL, type: reference.catalog.type, id: reference.catalog.id, extra: extra
        )
        await ResponseCache.catalogs.store(items, for: key)
        return items
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
    ///
    /// `onUpdate` hears every addon's answer as it arrives. With `settle`, once
    /// a playable link has arrived the slower addons get only that long to
    /// answer; the ones still waiting are left out (the stream list asks them again).
    func streams(
        type: String, id: String, addons: [AddonSource],
        settle: Duration? = nil,
        onUpdate: (@Sendable ([StreamGroup]) async -> Void)? = nil
    ) async -> [StreamGroup] {
        let candidates = addons.filter { $0.supports(.stream, type: type, id: id) }

        return await withTaskGroup(of: (Int, StreamGroup)?.self) { group in
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
            var settling = false
            while let next = await group.next() {
                // The settle timer firing: stop waiting for the rest.
                guard let result = next else {
                    group.cancelAll()
                    break
                }
                results.append(result)
                let sorted = results.sorted { $0.0 < $1.0 }.map(\.1)
                await onUpdate?(sorted)
                if let settle, !settling, case .success(let streams) = result.1.result,
                   streams.contains(where: { if case .direct = $0.stream.kind { true } else { false } }) {
                    settling = true
                    group.addTask {
                        try? await Task.sleep(for: settle)
                        return nil
                    }
                }
                if results.count == candidates.count {
                    group.cancelAll()
                    break
                }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// External subtitles from every subtitles addon, preferred languages first.
    func subtitles(type: String, id: String, addons: [AddonSource], preferredLanguages: [String]) async -> [SubtitleItem] {
        let candidates = addons.filter { $0.supports(.subtitles, type: type, id: id) }
        let lists = await withTaskGroup(of: (Int, [SubtitleItem]).self) { group in
            for (offset, addon) in candidates.enumerated() {
                group.addTask {
                    let items = (try? await client.subtitles(base: addon.baseURL, type: type, id: id)) ?? []
                    return (offset, items)
                }
            }
            var results: [(Int, [SubtitleItem])] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
        func rank(_ item: SubtitleItem) -> Int {
            let code = SubtitleLanguage.code(for: item.lang)
            return preferredLanguages.firstIndex(of: code ?? "") ?? preferredLanguages.count
        }
        return lists.enumerated()
            .sorted { lhs, rhs in
                let left = rank(lhs.element), right = rank(rhs.element)
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    /// Subtitles grouped by the addon that offers them, preferred languages first
    /// within each addon, so the viewer can pick by source.
    func subtitleSources(type: String, id: String, addons: [AddonSource], preferredLanguages: [String]) async -> [SubtitleSource] {
        let candidates = addons.filter { $0.supports(.subtitles, type: type, id: id) }
        let sources = await withTaskGroup(of: (Int, SubtitleSource).self) { group in
            for (offset, addon) in candidates.enumerated() {
                group.addTask {
                    let items = (try? await client.subtitles(base: addon.baseURL, type: type, id: id)) ?? []
                    return (offset, SubtitleSource(addon: addon, items: items))
                }
            }
            var results: [(Int, SubtitleSource)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        func rank(_ item: SubtitleItem) -> Int {
            preferredLanguages.firstIndex(of: SubtitleLanguage.code(for: item.lang) ?? "") ?? preferredLanguages.count
        }
        return sources.compactMap { source in
            guard !source.items.isEmpty else { return nil }
            var sorted = source
            sorted.items = source.items.enumerated()
                .sorted { lhs, rhs in
                    let left = rank(lhs.element), right = rank(rhs.element)
                    return left == right ? lhs.offset < rhs.offset : left < right
                }
                .map(\.element)
            return sorted
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

/// Normalises the language codes subtitle addons use ("ara", "eng", "pob"…).
enum SubtitleLanguage {
    private static let threeLetter: [String: String] = [
        "ara": "ar", "eng": "en", "fre": "fr", "fra": "fr", "spa": "es", "spn": "es", "ger": "de", "deu": "de",
        "ita": "it", "por": "pt", "pob": "pt", "pt-br": "pt", "rus": "ru", "tur": "tr", "jpn": "ja", "kor": "ko",
        "chi": "zh", "zho": "zh", "hin": "hi", "per": "fa", "fas": "fa", "heb": "he", "dut": "nl", "nld": "nl",
        "pol": "pl", "swe": "sv", "ind": "id", "may": "ms", "msa": "ms", "urd": "ur", "gre": "el", "ell": "el",
    ]

    /// An ISO 639-1 code ("ar") for whatever the addon sent, if recognised.
    static func code(for raw: String?) -> String? {
        guard let raw = raw?.lowercased().trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let mapped = threeLetter[raw] { return mapped }
        if raw.count == 2 { return raw }
        if raw.hasPrefix("arab") { return "ar" }
        if raw.hasPrefix("engl") { return "en" }
        return nil
    }
}

/// The subtitles one addon offers for a video.
struct SubtitleSource: Sendable, Identifiable {
    var addon: AddonSource
    var items: [SubtitleItem]

    var id: String { addon.id }
}
